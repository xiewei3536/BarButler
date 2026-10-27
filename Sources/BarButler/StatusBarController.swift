import AppKit
import ApplicationServices
import Combine
import ServiceManagement

/// 展開的原因 → 決定自動收合的節奏
enum ExpandReason { case click, hover, forward, peek, other }

enum IconStyleKit {
    static func symbolName(style: String, collapsed: Bool) -> String {
        switch style {
        case "dots":   return collapsed ? "ellipsis.circle.fill" : "ellipsis.circle"
        case "arrows": return collapsed ? "arrow.right.to.line.compact" : "arrow.left.to.line.compact"
        case "pill":   return collapsed ? "capsule.portrait.fill" : "capsule.portrait"
        default:       return collapsed ? "chevron.right" : "chevron.left"
        }
    }
}

/// 核心：使用者看得到的只有一個 ‹（toggle）。
///   [永久隱藏區…] ▏alwaysSep（選用）  [要收合的圖示…]  ▏pusher（1px 隱形）  ‹ toggle  [永遠顯示…]
/// 收合時把 pusher 的 length 撐到 10000，把它左邊的圖示全部擠出畫面。
/// pusher 永遠自動黏在 ‹ 左側、無圖示、不可點擊——單圖示外觀 + 穩定機制。
///
/// 穩定性原則（v1.4）：
/// 1. 只在系統穩定時（SystemMonitor.isStable）依幾何位置做判斷——睡眠、暗喚醒、換螢幕期間一律不動。
/// 2. 修正一律「非破壞」：先展開、再重新貼齊 pusher；萬不得已只重建自己的項目，絕不清空位置紀錄。
/// 3. ‹ 的位置另存備份；系統紀錄被刪（removeStatusItem 會刪）時用備份還原，重新啟動也維持原配置。
final class StatusBarController: NSObject, NSMenuDelegate {
    static weak var current: StatusBarController?

    static let toggleWidth: CGFloat = 24
    static let pusherIdle: CGFloat = 1
    static let pusherBoundary: CGFloat = 9
    static let sepWidth: CGFloat = 10
    static let hugeWidth: CGFloat = 10000
    private static let backupKey = "bb.togglePositionBackup"

    private let prefs = Prefs.shared
    private let bar = NSStatusBar.system
    private var toggleItem: NSStatusItem!
    private var pusher: NSStatusItem!
    private var alwaysSep: NSStatusItem!

    private(set) lazy var floatBar: FloatBar = {
        let f = FloatBar()
        f.owner = self
        return f
    }()

    private var collapseTimer: Timer?
    private var watchdog: Timer?
    private var peeking = false
    private var alwaysRevealed = false
    private var expandReason: ExpandReason = .other
    /// 正在調整自己的項目（重建、補寫位置）：可巢狀，用計數避免一個操作提早解除另一個操作的保護
    private var adjustDepth = 0
    private var isAdjusting: Bool { adjustDepth > 0 }
    private var peekRestoreCollapsed = false
    private var forwardToken = 0
    private var validateWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var boundaryVisible = false
    private var clickAwayMonitor: Any?
    private var dragMonitors: [Any] = []
    private var forwardPending = false
    private var lastForwardTime = Date.distantPast
    private var borrowed = false
    private var normalMainMenu: NSMenu?
    private weak var previousApp: NSRunningApplication?
    private var menuOpen = false
    private var cancellables = Set<AnyCancellable>()

    // 代為移動圖示期間：暫時展開、顯示分界線、停用自動收合與各種守衛（editDepth = 進行中的移動數）
    private(set) var editing = false
    private var editDepth = 0
    private var editRestoreCollapsed = false
    private var endEditWork: DispatchWorkItem?

    // 配置記憶（自動歸位）
    private var restoreInFlight = false
    private var restorePending = false   // 有圖示因選單列太擠暫時移不了，等切換 App 再試
    private(set) var pendingRestoreCount = 0  // 與記憶不符、還沒歸位的圖示數（面板上顯示「歸位」）
    private var restoreBackoffUntil = Date.distantPast
    private var restoreBackoff: TimeInterval = 30
    private var knownWindowIDs = Set<Int>()
    private var lastKnownSections: [Int: BarSection] = [:]   // 上次健康檢查時各圖示的區塊（判斷使用者拖了哪個）
    private var arranging = false        // 使用者正在按住 ⌘ 拖曳圖示
    private var lastUserArrange = Date.distantPast
    private var localDragMonitors: [Any] = []

    // 穩定守護
    private var offscreenStrikes = 0
    private var recoveryAttempts: [Date] = []   // 修復退避：10 分鐘內最多 2 次，之後等下一次系統過渡再試
    private var overflowStrikes = 0
    private(set) var lastHealthCheck: Date?
    private(set) var lastHealthNote = "—"
    private(set) var repairCount = UserDefaults.standard.integer(forKey: "bb.repairCount")

    private(set) var collapsed: Bool

    /// ‹ 在螢幕上的位置（NSScreen 座標；x 軸與 CGWindow 全域座標一致）
    var arrowScreenFrame: NSRect? { toggleItem?.button?.window?.frame }
    var arrowScreenMinX: CGFloat? { arrowScreenFrame?.minX }
    var isBorrowingMenuBar: Bool { borrowed }

    override init() {
        collapsed = prefs.collapsed
        super.init()
        Self.current = self

        migratePositionSchema()
        buildItems()
        apply()
        observePositionDefaults()
        installDragMonitors()
        startWatchdog()

        SystemMonitor.shared.onSettled { [weak self] why in self?.systemSettled(why) }
        SystemMonitor.shared.onWillSleep { [weak self] in self?.prepareForSleep() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let s = self, s.restorePending else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { s.restoreLayoutIfNeeded("app switched") }
            }

        // 啟動後等版面穩定再檢查一次（pusher 是否貼緊 ‹、位置紀錄是否完整），再把被打亂的圖示歸位
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.healthCheck("launch") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in self?.restoreLayoutIfNeeded("launch") }

        let reapply: (Any) -> Void = { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
        prefs.$alwaysHiddenEnabled.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$language.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$iconStyle.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$clickAwayCollapse.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$clickMode.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.floatBar.close(); self?.apply() } }
            .store(in: &cancellables)
    }

    // MARK: - 位置鍵

    private static func posKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// 距右端距離，越小越靠右；nil = 尚未有紀錄
    private func position(_ name: String) -> Double? {
        (UserDefaults.standard.object(forKey: Self.posKey(name)) as? NSNumber)?.doubleValue
    }

    private var positionBackup: Double? {
        (UserDefaults.standard.object(forKey: Self.backupKey) as? NSNumber)?.doubleValue
    }

    /// v1.1.1 起採用 pusher 架構：清除舊紀錄並把 ‹ 放到最右側。
    /// ‹ 的系統紀錄不見時（被 removeStatusItem 刪掉、或舊版誤修復）改用自備備份，避免 ‹ 被放到最左邊。
    private func migratePositionSchema() {
        let d = UserDefaults.standard
        if !d.bool(forKey: "posSchemaV2") {
            for n in ["BB_Toggle", "BB_HideSep", "BB_Pusher", "BB_AlwaysSep"] {
                d.removeObject(forKey: Self.posKey(n))
                d.removeObject(forKey: "NSStatusItem Visible \(n)")
            }
            d.set(true, forKey: "posSchemaV2")
        }
        if position("BB_Toggle") == nil {
            let v = positionBackup ?? 1.0
            d.set(v, forKey: Self.posKey("BB_Toggle"))
            Log.event("launch: ‹ position missing → \(positionBackup == nil ? "right end" : "backup \(v)")")
        }
    }

    private func beginAdjust() { adjustDepth += 1 }

    /// after: nil = 立即解除；0 = 下一輪 run loop（讓 AppKit 建立項目時同步寫入的位置通知先過去）
    private func endAdjust(after delay: TimeInterval? = nil) {
        let work = { [weak self] in
            guard let s = self else { return }
            s.adjustDepth = max(0, s.adjustDepth - 1)
        }
        if let delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }

    // MARK: - 建立狀態列項目

    private func buildItems() {
        beginAdjust()
        defer { endAdjust(after: 0) }

        toggleItem = makeToggle()
        buildPusher()
        alwaysSep = bar.statusItem(withLength: Self.hugeWidth)
        alwaysSep.autosaveName = "BB_AlwaysSep"
    }

    private func makeToggle() -> NSStatusItem {
        let item = bar.statusItem(withLength: Self.toggleWidth)
        item.autosaveName = "BB_Toggle"
        item.isVisible = true
        if let b = item.button {
            b.target = self
            b.action = #selector(toggleClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel("BarButler")
            b.addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }
        return item
    }

    /// pusher 永遠黏在 ‹ 左側（位置值 = ‹ + 0.5）。removeStatusItem 會刪掉紀錄，所以刪除後才寫入。
    private func buildPusher(anchor explicit: Double? = nil) {
        if let p = pusher { bar.removeStatusItem(p) }
        let anchor = explicit ?? position("BB_Toggle") ?? toggleGeometryDistance ?? 1.0
        UserDefaults.standard.set(anchor + 0.5, forKey: Self.posKey("BB_Pusher"))
        pusher = bar.statusItem(withLength: collapsed ? Self.hugeWidth : Self.pusherIdle)
        pusher.autosaveName = "BB_Pusher"
        pusher.isVisible = true
        pusher.button?.isEnabled = false // 不可點擊、無圖示 → 使用者感知不到它
    }

    /// ‹ 的「距右端距離」，與系統寫入 Preferred Position 的算法相同（螢幕右緣 − 視窗右緣）
    private var toggleGeometryDistance: Double? {
        guard let w = toggleItem?.button?.window, w.frame.width > 0,
              let screen = w.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(w.frame) }) else { return nil }
        return Double(screen.frame.maxX - w.frame.maxX)
    }

    /// 真相來源：pusher 必須在 ‹「左側」且緊貼（方向性檢查，避免 ‹ 被拖到 pusher 左邊而不知）
    private var pusherAdjacent: Bool {
        guard let tw = toggleItem?.button?.window,
              let pw = pusher?.button?.window else { return false }
        let gap = tw.frame.minX - pw.frame.maxX
        return gap >= -2 && gap <= 30
    }

    /// 只看水平位置：選單列自動隱藏、全螢幕 App 時，狀態列視窗會被移到螢幕上緣之外，那不算出界
    private var toggleOnScreen: Bool {
        guard let w = toggleItem?.button?.window, w.frame.width > 0 else { return false }
        return ScreenGeometry.xOnSomeScreen(w.frame.midX)
    }

    /// 確保 pusher 就位後再執行後續動作（收合前必經）。過渡期不重建，交給穩定後的健康檢查。
    private func syncPusher(then completion: (() -> Void)? = nil) {
        guard !collapsed, !editing, !pusherAdjacent, SystemMonitor.shared.isStable else { completion?(); return }
        Log.event("divider not next to ‹ → re-anchor")
        beginAdjust()
        buildPusher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let s = self else { return }
            if !s.pusherAdjacent, let g = s.toggleGeometryDistance {
                s.buildPusher(anchor: g)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                s.endAdjust()
                s.apply()
                if !s.pusherAdjacent { Log.event("re-anchor failed; will retry on next check") }
                completion?()
            }
        }
    }

    /// 只重建我們自己的項目（不碰其他 App）；先刪除再寫入位置，最後再補寫一次（刪除可能是延遲生效）
    private func recreateToggle(at value: Double, completion: (() -> Void)? = nil) {
        Log.event("recreate ‹ at position \(value)")
        beginAdjust()
        if let t = toggleItem { bar.removeStatusItem(t) }
        if let p = pusher { bar.removeStatusItem(p) }
        pusher = nil
        UserDefaults.standard.set(value, forKey: Self.posKey("BB_Toggle"))
        toggleItem = makeToggle()
        buildPusher(anchor: value)
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let s = self else { return }
            s.apply()
            s.writeOwnPositions(force: true)
            s.endAdjust()
            if !s.collapsed, !s.pusherAdjacent { s.syncPusher() }
            completion?()
        }
    }

    // MARK: - 位置守衛（使用者 ⌘ 拖曳後系統會改寫位置紀錄 → 校正）

    private func observePositionDefaults() {
        for n in ["BB_Toggle", "BB_Pusher", "BB_AlwaysSep"] {
            UserDefaults.standard.addObserver(self, forKeyPath: Self.posKey(n), options: [.new], context: nil)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath?.hasPrefix("NSStatusItem Preferred Position") == true else { return }
        DispatchQueue.main.async { [weak self] in
            guard let s = self, !s.isAdjusting, !s.editing else { return }
            s.validateWork?.cancel()
            let work = DispatchWorkItem { [weak s] in s?.validatePositions() }
            s.validateWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func validatePositions() {
        guard !isAdjusting, !editing, !collapsed, SystemMonitor.shared.isStable else { return }
        if !pusherAdjacent { syncPusher(); return }   // 使用者拖動了 ‹ → pusher 自動跟上
        if alwaysSepMisplaced { healAlwaysSep(); return }
        backupPositions()
    }

    /// 永久隱藏區分隔線必須在 ‹ 左側
    private var alwaysSepMisplaced: Bool {
        guard prefs.alwaysHiddenEnabled, alwaysSep.isVisible,
              let tw = toggleItem.button?.window, let aw = alwaysSep.button?.window,
              aw.frame.width > 0 else { return false }
        return aw.frame.minX > tw.frame.minX
    }

    /// 只修永久隱藏區分隔線：移回最左側（不會把任何圖示誤收進永久隱藏），不動 ‹ 的位置
    private func healAlwaysSep() {
        guard !isAdjusting else { return }
        Log.event("always-hidden divider right of ‹ → move to left end")
        beginAdjust()
        bar.removeStatusItem(alwaysSep)
        UserDefaults.standard.set(99_999, forKey: Self.posKey("BB_AlwaysSep"))
        alwaysSep = bar.statusItem(withLength: Self.hugeWidth)
        alwaysSep.autosaveName = "BB_AlwaysSep"
        apply()
        Toast.show(L.toastFixed.s, kind: .info, near: arrowScreenFrame)
        endAdjust(after: 1.0)
    }

    /// 系統紀錄不見時補寫（以實際位置換算），並更新自備備份
    private func writeOwnPositions(force: Bool = false) {
        guard SystemMonitor.shared.isStable, toggleOnScreen, let g = toggleGeometryDistance else { return }
        let d = UserDefaults.standard
        beginAdjust()   // 我們自己寫入，別觸發 KVO 校正
        if force || position("BB_Toggle") == nil {
            d.set(g.rounded(), forKey: Self.posKey("BB_Toggle"))
        }
        if pusherAdjacent, force || position("BB_Pusher") == nil {
            d.set(g.rounded() + 0.5, forKey: Self.posKey("BB_Pusher"))
        }
        endAdjust(after: 0)
        backupPositions()
    }

    private func backupPositions() {
        guard let v = position("BB_Toggle") ?? toggleGeometryDistance else { return }
        if positionBackup != v { UserDefaults.standard.set(v, forKey: Self.backupKey) }
    }

    // MARK: - 穩定守護（看門狗＋喚醒／換螢幕後的檢查）

    private func startWatchdog() {
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.healthCheck("watchdog") }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func prepareForSleep() {
        hoverWork?.cancel()
        validateWork?.cancel()
        offscreenStrikes = 0
        ItemMover.cancelRequested = true      // 移動中途要睡了：停下來，醒來後再歸位
        endForward()
        restoreMenuBarIfBorrowed()
        floatBar.close()
    }

    private func systemSettled(_ why: String) {
        if !menuOpen { toggleItem.menu = nil }
        recoveryAttempts.removeAll()          // 新的過渡期：修復與歸位的退避重新計算
        restoreBackoffUntil = .distantPast
        restoreBackoff = 30
        apply()
        healthCheck(why)
        // 外接螢幕喚醒後常會再換一次解析度：幾秒後複查，再把被打亂的圖示歸位
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.healthCheck("\(why)+6s")
            self?.restoreLayoutIfNeeded(why)
        }
    }

    /// 健康檢查：只在系統穩定時進行；所有修正都不刪除使用者的配置
    func healthCheck(_ why: String) {
        lastHealthCheck = Date()
        if why == "manual" || why == "url" { recoveryAttempts.removeAll(); lastHealthNote = "—" }
        SystemMonitor.shared.reconcile()
        guard SystemMonitor.shared.isStable else { lastHealthNote = "waiting for system to settle"; return }
        guard !isAdjusting, !editing, !peeking, !forwardPending, !floatBar.isOpen else { return }
        guard toggleItem.button?.window?.frame.width ?? 0 > 0 else {
            guard mayRepair("no window") else { return }
            Log.event("health(\(why)): ‹ has no window → recreate")
            noteRepair()
            recreateToggle(at: positionBackup ?? 1.0)
            return
        }
        if !toggleOnScreen {
            offscreenStrikes += 1
            let f = toggleItem.button?.window?.frame ?? .zero
            Log.event("health(\(why)): ‹ off-screen strike \(offscreenStrikes) at x=\(Int(f.minX)) y=\(Int(f.minY))")
            if offscreenStrikes >= 2 {
                recoverOffscreen()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.healthCheck("recheck") }
            }
            return
        }
        offscreenStrikes = 0
        if collapsed {
            if pusher.length < Self.hugeWidth { apply() }
            if !pusherAdjacent { repairCollapsedDivider(); return }
        } else {
            if !pusherAdjacent { syncPusher(); lastHealthNote = "re-anchored divider"; return }
            if alwaysSepMisplaced { healAlwaysSep(); return }
        }
        if position("BB_Toggle") == nil || (!collapsed && position("BB_Pusher") == nil) { writeOwnPositions() }
        backupPositions()
        checkToggleOverflow()
        watchForNewItems()
        if lastHealthNote != "repair paused" { lastHealthNote = "ok" }
    }

    /// 修復退避：10 分鐘內最多兩次；之後要等下一次系統過渡（喚醒、換螢幕）或手動檢查才再試，
    /// 避免與其他選單列管理工具（同樣用超寬項目擠圖示）無止盡地互相拉扯
    private func mayRepair(_ what: String) -> Bool {
        let now = Date()
        recoveryAttempts = recoveryAttempts.filter { now.timeIntervalSince($0) < 600 }
        guard recoveryAttempts.count < 2 else {
            if lastHealthNote != "repair paused" { Log.event("repair paused (\(what)): too many attempts, waiting for next settle") }
            lastHealthNote = "repair paused"
            return false
        }
        recoveryAttempts.append(now)
        return true
    }

    /// 收合中 pusher 卻沒貼著 ‹（中間夾著本該收起的圖示）：短暫展開、重新貼齊、再收合
    private func repairCollapsedDivider() {
        guard mayRepair("divider") else { return }
        Log.event("collapsed but divider not next to ‹ → expand, re-anchor, collapse")
        noteRepair()
        beginAdjust()
        collapsed = false
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let s = self else { return }
            s.endAdjust()
            s.syncPusher { [weak s] in s?.reallySetCollapsed(true, reason: .other) }
        }
    }

    /// ‹ 在穩定狀態下連續兩次不在任何螢幕上：先展開（多半是被排到 pusher 左邊），不行才重建 ‹
    private func recoverOffscreen() {
        offscreenStrikes = 0
        guard mayRepair("off-screen") else { return }
        noteRepair()
        Log.event("recover: ‹ off-screen → expand first")
        beginAdjust()
        let wasCollapsed = collapsed
        collapsed = false
        alwaysRevealed = prefs.alwaysHiddenEnabled
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let s = self else { return }
            s.endAdjust()
            s.alwaysRevealed = false
            s.apply()
            let finish = { [weak s] in
                guard let s else { return }
                if wasCollapsed { s.setCollapsed(true, reason: .other) } else { s.prefs.collapsed = false }
            }
            if s.toggleOnScreen {
                Log.event("recover: ‹ visible after expanding → re-anchor dividers")
                s.syncPusher { [weak s] in
                    guard let s else { return }
                    if s.alwaysSepMisplaced { s.healAlwaysSep() }
                    finish()
                }
            } else {
                s.recreateToggle(at: s.positionBackup ?? 1.0, completion: finish)
            }
            Toast.show(L.toastRecovered.s, kind: .info, near: s.arrowScreenFrame)
        }
    }

    private func noteRepair() {
        repairCount += 1
        UserDefaults.standard.set(repairCount, forKey: "bb.repairCount")
        lastHealthNote = "repaired"
    }

    /// ‹ 自己被 macOS 因空間不足藏起來（點不到）：持續約一分鐘就提示一次（每天最多一次）
    private func checkToggleOverflow() {
        guard let id = toggleItem.button?.window?.windowNumber, id > 0,
              let w = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]])?.first
        else { return }
        // 鎖定畫面、全螢幕 App、選單列自動隱藏時 ‹ 本來就看不到，不算「被擠掉」
        guard NSMenu.menuBarVisible(), !SystemMonitor.shared.screenLocked else { overflowStrikes = 0; return }
        let hidden = (w[kCGWindowIsOnscreen as String] as? Bool) != true
        overflowStrikes = hidden ? overflowStrikes + 1 : 0
        guard overflowStrikes >= 3 else { return }
        overflowStrikes = 0
        let d = UserDefaults.standard
        guard Date().timeIntervalSince1970 - d.double(forKey: "bb.lastCrowdedTip") > 86_400 else { return }
        d.set(Date().timeIntervalSince1970, forKey: "bb.lastCrowdedTip")
        Log.event("‹ is hidden by menu bar overflow")
        let hk = prefs.hotkeyEnabled ? HotkeyManager.display(keyCode: prefs.hotkeyKeyCode, modifiersRaw: prefs.hotkeyModifiers) : "—"
        Toast.show(L.toastCrowded.f(hk), kind: .warning, near: arrowScreenFrame, duration: 6)
    }

    var healthSummary: String {
        "collapsed=\(collapsed) editing=\(editing) adjacent=\(pusherAdjacent) onScreen=\(toggleOnScreen) "
            + "pos=\(position("BB_Toggle").map { String($0) } ?? "nil")/\(position("BB_Pusher").map { String($0) } ?? "nil") "
            + "backup=\(positionBackup.map { String($0) } ?? "nil") repairs=\(repairCount) note=\(lastHealthNote)"
    }

    // MARK: - 狀態套用

    private func apply() {
        guard toggleItem != nil, pusher != nil, alwaysSep != nil else { return }
        if let b = toggleItem.button {
            b.image = Self.symbol(IconStyleKit.symbolName(style: prefs.iconStyle, collapsed: collapsed))
            let tip = prefs.isFloatMode ? L.tooltipFloat.s : L.tooltipMenubar.s
            if b.toolTip != tip { b.toolTip = tip }
        }
        if collapsed {
            pusher.length = Self.hugeWidth
            pusher.button?.image = nil
        } else if boundaryVisible || editing {
            pusher.length = Self.pusherBoundary
            pusher.button?.image = Self.separatorImage(alpha: editing ? 0.85 : 0.6)
        } else {
            pusher.length = Self.pusherIdle
            pusher.button?.image = nil
        }

        let alwaysOn = prefs.alwaysHiddenEnabled
        if alwaysSep.isVisible != alwaysOn { alwaysSep.isVisible = alwaysOn }
        if alwaysOn {
            let show = (alwaysRevealed || peeking || editing) && !collapsed
            alwaysSep.length = show ? Self.sepWidth : Self.hugeWidth
            alwaysSep.button?.image = show ? Self.separatorImage(alpha: 0.5) : nil
        }
        updateClickAwayMonitor()
    }

    // MARK: - 收合／展開

    func setCollapsed(_ c: Bool, reason: ExpandReason = .click) {
        // 收合前先確保 pusher 貼緊 ‹，才會把正確的區塊藏起來
        if c, !collapsed, !pusherAdjacent {
            syncPusher { [weak self] in self?.reallySetCollapsed(true, reason: reason) }
            return
        }
        reallySetCollapsed(c, reason: reason)
    }

    private func reallySetCollapsed(_ c: Bool, reason: ExpandReason) {
        Log.core.info("setCollapsed \(c) reason=\(String(describing: reason))")
        peeking = false
        hoverWork?.cancel()
        if editing { editing = false; editDepth = 0; endEditWork?.cancel() }
        collapsed = c
        prefs.collapsed = c
        if c {
            alwaysRevealed = false
            boundaryVisible = false
            expandReason = .other
            cancelTimer()
            apply()
            restoreMenuBarIfBorrowed()
            maybeShowCollapseHint()
        } else {
            expandReason = reason
            apply()
            scheduleCollapse()
            if reason == .click || reason == .other { checkOverflowAfterExpand() }
        }
    }

    func toggle() { setCollapsed(!collapsed, reason: .click) }
    func hide() { if !collapsed { setCollapsed(true) } }
    func show() { if collapsed { setCollapsed(false, reason: .click) } }

    /// 主要進入點（左鍵／快捷鍵）：依使用者選擇的模式行動
    func activate() {
        Log.core.info("activate float=\(self.prefs.isFloatMode) collapsed=\(self.collapsed)")
        SystemMonitor.shared.noteUserActivity()
        if prefs.isFloatMode {
            if !collapsed && !floatBar.isOpen { setCollapsed(true) } // 已展開時點 ‹ = 收合
            else { floatBar.toggle() }
        } else {
            if collapsed, prefs.borrowOnExpand, needsRoom(forTarget: nil) { borrowMenuBar() }
            toggle()
        }
    }

    private func toggleAlwaysRevealed() {
        guard prefs.alwaysHiddenEnabled else { toggle(); return }
        if collapsed {
            setCollapsed(false, reason: .click)
            alwaysRevealed = true
        } else {
            alwaysRevealed.toggle()
        }
        scheduleCollapse()
        apply()
    }

    /// 快速一覽：全部顯示 N 秒後恢復
    func peek(seconds: TimeInterval = 5) {
        guard !peeking, !editing else { return }
        peeking = true
        let restoreCollapsed = collapsed
        let restoreRevealed = alwaysRevealed
        peekRestoreCollapsed = restoreCollapsed
        collapsed = false
        expandReason = .peek
        cancelTimer()
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let s = self, s.peeking else { return }
            s.peeking = false
            s.collapsed = restoreCollapsed
            s.alwaysRevealed = restoreRevealed
            s.expandReason = .other
            s.apply()
            if !s.collapsed { s.scheduleCollapse() }
        }
    }

    // MARK: - 圖示配置（ItemMover／圖示配置頁／面板右鍵呼叫）

    func snapshot(details: Bool = true) -> BarSnapshot {
        guard let t = toggleItem?.button?.window?.windowNumber, t > 0 else { return .empty }
        let p = pusher?.button?.window?.windowNumber
        let s = prefs.alwaysHiddenEnabled ? alwaysSep?.button?.window?.windowNumber : nil
        return BarScanner.snapshot(own: .init(toggle: t, pusher: p, sep: s), details: details)
    }

    /// 移動期間：暫時展開（不寫入偏好）、顯示分界線，讓所有圖示都在畫面上
    func beginEditing() {
        endEditWork?.cancel()
        editDepth += 1
        guard !editing else { return }
        editing = true
        editRestoreCollapsed = peeking ? peekRestoreCollapsed : collapsed
        hoverWork?.cancel()
        cancelTimer()
        peeking = false
        collapsed = false
        apply()
    }

    /// 結束移動（延遲執行，連續移動多個圖示時不會一直收合又展開）
    func endEditing(after delay: TimeInterval = 1.4) {
        editDepth = max(0, editDepth - 1)
        guard editDepth == 0 else { return }       // 還有其他移動在進行
        endEditWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self, s.editing, s.editDepth == 0 else { return }
            s.editing = false
            s.alwaysRevealed = false
            if s.editRestoreCollapsed {
                s.reallySetCollapsed(true, reason: .other)
            } else {
                s.apply()
                s.scheduleCollapse()
            }
            s.restoreMenuBarIfBorrowed()           // 為了移動而借的選單列一定要還
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { s.healthCheck("after-edit") }
        }
        endEditWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    /// 由使用者點擊觸發（面板右鍵選單）：必要時「當下」借用選單列騰出空間，再交給 ItemMover
    func moveItem(_ item: BarItem, to dest: BarSection) {
        guard item.section != dest else { return }
        // 先把一定會失敗的情況擋掉，免得白白借用選單列（借了就得確定會還）
        let blocker: String? = !item.movable ? L.itemLocked.s
            : !AXPresser.trusted ? L.moveNeedsAX.s
            : !SystemMonitor.shared.canPostEvents ? L.moveLocked.s
            : ItemMover.isMoving ? L.moveBusy.s : nil
        if let blocker {
            Toast.show(blocker, kind: .warning, near: arrowScreenFrame)
            if !AXPresser.trusted { AXPresser.promptForPermission() }
            return
        }
        // 常駐 → 收合：只要 ‹ 看得到就有落點；收合 → 其他：來源圖示展開後必須擠得進選單列
        let ownMenuBar = NSApp.isActive && NSApp.activationPolicy() == .regular
        let anchorsVisible = snapshot(details: false).anchorsVisible
        let needs = item.section == .shown ? !anchorsVisible : (!anchorsVisible || needsRoom(forTarget: item.windowID))
        if !ownMenuBar, needs { borrowMenuBar() }
        Task { @MainActor in
            do {
                try await ItemMover.shared.move(windowID: item.windowID, to: dest, via: self)
                self.rememberMove(item.windowID, to: dest)
                Toast.show(L.movedFmt.f(item.label, dest.title), kind: .success, near: self.arrowScreenFrame)
            } catch {
                Toast.show(ItemMover.message(for: error, label: item.label), kind: .warning, near: self.arrowScreenFrame)
            }
            if !self.editing { self.restoreMenuBarIfBorrowed() }  // 沒進入編輯就失敗：endEditing 不會替我們還
        }
    }

    /// 「全部收起」：‹ 移到最右端（其他圖示全部進收合區）；「全部顯示」：‹ 移到最左端
    func relocateToggle(rightEnd: Bool) {
        Log.event("relocate ‹ → \(rightEnd ? "right end" : "left end")")
        recreateToggle(at: rightEnd ? 1.0 : 99_999)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.rememberLayout(rightEnd ? "hide all" : "show all")
        }
    }

    // MARK: - 配置記憶（自動歸位）

    /// 以目前畫面為準記住每個圖示的區塊（使用者確認過的整體配置：全部收起／顯示、開啟記憶）
    func rememberLayout(_ reason: String) {
        guard prefs.rememberLayout, AXPresser.trusted else { return }
        LayoutMemory.shared.record(snapshot(), reason: reason)
    }

    /// 使用者移動了一個圖示：只記這一個（其他圖示若正等著歸位，不能順便把錯的位置記下來）。
    /// 還沒有任何記憶時，以目前整條選單列為起點。
    func rememberMove(_ windowID: Int, to dest: BarSection) {
        guard prefs.rememberLayout, AXPresser.trusted else { return }
        let snap = snapshot()
        if LayoutMemory.shared.pins.isEmpty {
            LayoutMemory.shared.record(snap, reason: "first move")
        } else {
            LayoutMemory.shared.pin(windowID, to: dest, in: snap)
        }
        lastKnownSections = Self.sections(of: snap)
    }

    /// 使用者自己 ⌘ 拖曳完：和拖曳前（上次健康檢查）比對，只記換了區塊的圖示
    private func rememberUserArrangement() {
        guard prefs.rememberLayout, AXPresser.trusted else { return }
        let snap = snapshot()
        if LayoutMemory.shared.pins.isEmpty || lastKnownSections.isEmpty {
            LayoutMemory.shared.record(snap, reason: "user ⌘-drag")
        } else {
            let changed = snap.items.filter { it in
                guard let was = lastKnownSections[it.windowID] else { return false }
                return was != it.section
            }
            for it in changed { LayoutMemory.shared.pin(it.windowID, to: it.section, in: snap) }
        }
        lastKnownSections = Self.sections(of: snap)
    }

    private static func sections(of snap: BarSnapshot) -> [Int: BarSection] {
        Dictionary(snap.items.map { ($0.windowID, $0.section) }, uniquingKeysWith: { a, _ in a })
    }

    /// 與記憶不符的圖示自動移回原區塊。只在系統穩定、使用者沒在操作時進行；同一圖示失敗 3 次就不再嘗試
    /// force = 使用者在面板按了「歸位」：已在點擊當下借好選單列，不看空間預測、不等閒置
    func restoreLayoutIfNeeded(_ why: String, attempt: Int = 0, force: Bool = false) {
        guard prefs.rememberLayout, AXPresser.trusted, !restoreInFlight, SystemMonitor.shared.isStable else { return }
        guard force || Date() >= restoreBackoffUntil else { restorePending = true; return }   // 剛因空間不足失敗過：退避中
        let snap = snapshot()
        let all = LayoutMemory.shared.mismatches(snap, alwaysEnabled: prefs.alwaysHiddenEnabled)
        pendingRestoreCount = all.count
        guard !all.isEmpty else {
            restorePending = false
            if force { restoreMenuBarIfBorrowed() }   // 為了歸位借的選單列：沒事可做也要還
            return
        }
        // 暫時性的阻礙（使用者正在操作、選單或面板開著、正在修復…）：稍後再試，不要默默放棄
        let busy = ItemMover.isMoving || !SystemMonitor.shared.canPostEvents || editing || peeking || forwardPending
            || floatBar.isOpen || menuOpen || isAdjusting || arranging
            || (!force && (borrowed || Date().timeIntervalSince(lastUserArrange) < 5 || Self.secondsSinceInput < 1.5))
        if busy {
            restorePending = true
            if attempt < 12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.restoreLayoutIfNeeded(why, attempt: attempt + 1, force: force)
                }
            } else if force {
                restoreMenuBarIfBorrowed()
            }
            return
        }
        // 收合區的圖示要先展開才拖得到：前景 App 選單太長、展開後會被 macOS 擠掉的，先不動，等切換 App 再試
        let todo = force ? all : all.filter { item, _ in
            snap.anchorsVisible && (item.section == .shown || !needsRoom(forTarget: item.windowID))
        }
        restorePending = todo.count < all.count
        if restorePending { Log.event("restore deferred for \(all.count - todo.count) icon(s): menu bar too full right now") }
        guard !todo.isEmpty else { return }
        restoreInFlight = true
        Log.event("restore layout (\(why)): " + todo.map { "\($0.0.label) → \($0.1)" }.joined(separator: ", "))
        Task { @MainActor in
            var moved = 0
            pass: for (item, dest) in todo {
                guard SystemMonitor.shared.canPostEvents, !self.arranging else { self.restorePending = true; break }
                do {
                    try await ItemMover.shared.move(windowID: item.windowID, to: dest, via: self, interactive: force)
                    moved += 1
                } catch let f as ItemMover.Failure {
                    Log.event("restore \(item.label) failed: \(f)")
                    switch f {
                    case .notVisible:       // 空間不足：退避（30 秒起跳、加倍、最多 30 分鐘），其他的多半也放不下
                        self.restorePending = true
                        self.restoreBackoffUntil = Date().addingTimeInterval(self.restoreBackoff)
                        self.restoreBackoff = min(self.restoreBackoff * 2, 1800)
                        break pass
                    case .didNotMove, .unmovable:
                        LayoutMemory.shared.noteFailure(item, in: snap)
                    case .collateral:       // 拖錯了：停下來，下次檢查再說
                        LayoutMemory.shared.noteFailure(item, in: snap)
                        break pass
                    default:                // 鎖定、睡眠、忙碌、圖示消失：不算失敗，下次再來
                        self.restorePending = true
                        break pass
                    }
                } catch {
                    break pass
                }
            }
            self.restoreInFlight = false
            self.pendingRestoreCount = max(0, all.count - moved)
            if moved > 0 {
                self.restoreBackoff = 30
                self.lastHealthNote = "restored \(moved) icon(s)"
            }
            if !self.editing { self.restoreMenuBarIfBorrowed() }
        }
    }

    /// 使用者在面板按「歸位」：在點擊當下借用選單列騰出空間（之後才借會被系統拒絕），立刻歸位
    func restoreNow() {
        guard AXPresser.trusted, SystemMonitor.shared.canPostEvents, !restoreInFlight, !ItemMover.isMoving else { return }
        if !(NSApp.isActive && NSApp.activationPolicy() == .regular) { borrowMenuBar() }
        restoreBackoffUntil = .distantPast
        restoreBackoff = 30
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.restoreLayoutIfNeeded("user", force: true)
        }
    }

    /// 有新的圖示出現（App 啟動、更新後重開）→ 稍後檢查是否需要歸位
    private func watchForNewItems() {
        let snap = snapshot(details: false)
        let ids = Set(snap.items.map(\.windowID))
        if !arranging { lastKnownSections = Self.sections(of: snap) }
        defer { knownWindowIDs = ids }
        guard !knownWindowIDs.isEmpty, !ids.subtracting(knownWindowIDs).isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.restoreLayoutIfNeeded("new icon") }
    }

    private static var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    // MARK: - 面板代點（FloatBar 呼叫）

    /// 一步到位：展開 → 等目標「真的顯示」→ 合成點擊。若 0.6 秒後仍被藏（選單列空間不足），
    /// 借用選單列：讓 BarButler 短暫成為前景 App 騰出左側空間，收合時自動切回原 App。
    func forwardClick(toWindow id: Int, name: String) {
        // 必須在使用者點擊事件的同一時刻決定是否借位：macOS 14+ 只在互動當下允許 App 自行成為前景
        if needsRoom(forTarget: id) { borrowMenuBar() }
        let inAlways = snapshot(details: false).item(id)?.section == .alwaysHidden
        beginForward()
        if inAlways, !alwaysRevealed { alwaysRevealed = true; apply() }   // 永久隱藏區的圖示：暫時展開那一區
        var attempts = 0
        var stable = 0
        func tick() {
            guard forwardPending else { return }
            attempts += 1
            // 借位時要等我們真的成為前景（選單列已切換），且目標連續兩次輪詢都在畫面上才點，
            // 避免在選單列切換的瞬間誤點到前景 App 的選單
            let ready = !borrowed || NSApp.isActive
            if ready, let b = AXPresser.onscreenBounds(windowID: id) {
                stable += 1
                if stable >= 2 {
                    Log.panel.info("forward click → \(name, privacy: .public) at x=\(Int(b.midX)) after \(attempts) polls borrowed=\(self.borrowed) active=\(NSApp.isActive)")
                    AXPresser.click(at: CGPoint(x: b.midX, y: b.midY))
                    endForward()
                    return
                }
            } else {
                stable = 0
            }
            if attempts == 5, !borrowed { borrowMenuBar() }   // 備援：預測失準時再試一次（可能被系統拒絕）
            if attempts >= 24 {
                Log.event("forward failed: \(name) never became visible")
                Toast.show(L.toastOverflow.f(1), kind: .warning, near: arrowScreenFrame)
                endForward()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { tick() }
        }
        tick()
    }

    func beginForward() {
        lastForwardTime = Date()
        forwardPending = true
        forwardToken += 1
        let token = forwardToken
        if collapsed { setCollapsed(false, reason: .forward) } else { expandReason = .forward }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in   // 安全網（只管這一次）
            guard let s = self, s.forwardToken == token else { return }
            s.endForward()
        }
    }

    func endForward() {
        guard forwardPending else { return }
        forwardPending = false
        if !collapsed { scheduleCollapse(after: 1.0) }
    }

    // MARK: - 借用選單列（空間不足時）

    func borrowMenuBar() {
        guard !borrowed else { return }
        guard !(NSApp.isActive && NSApp.activationPolicy() == .regular) else { return } // 偏好設定開著：選單列已是我們的
        borrowed = true
        previousApp = NSWorkspace.shared.frontmostApplication
        normalMainMenu = NSApp.mainMenu
        // 換成沒有任何快捷鍵的迷你選單，避免借位期間 ⌘Q 之類誤傷
        let m = NSMenu()
        let appItem = NSMenuItem()
        let sub = NSMenu()
        let info = NSMenuItem(title: L.borrowMenuTitle.s, action: nil, keyEquivalent: "")
        info.isEnabled = false
        sub.addItem(info)
        appItem.submenu = sub
        m.addItem(appItem)
        NSApp.mainMenu = m
        // accessory App 即使 active 也拿不到選單列；必須暫時成為 regular App（Dock 會短暫出現圖示）
        AppActivation.require("borrow")
        NSApp.activate(ignoringOtherApps: true)
        Log.core.info("borrow menu bar from \(self.previousApp?.localizedName ?? "-", privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let s = self, s.borrowed else { return }
            Log.core.info("borrow result: isActive=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-", privacy: .public)")
            if !NSApp.isActive { s.restoreMenuBarIfBorrowed() } // 系統拒絕 → 立刻還原
        }
        // 輕推 pusher 1pt 再還原，強制狀態列依新的可用空間重新排版
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let s = self, !s.collapsed else { return }
            s.pusher.length += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { s.apply() }
        }
    }

    private func restoreMenuBarIfBorrowed() {
        guard borrowed else { return }
        borrowed = false
        if let normal = normalMainMenu { NSApp.mainMenu = normal }
        let weAreFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        if (NSApp.isActive || weAreFront), let prev = previousApp, !prev.isTerminated {
            prev.activate()
            Log.core.info("restore front app → \(prev.localizedName ?? "-", privacy: .public)")
        }
        previousApp = nil
        // 交還前景後再退回 accessory（Dock 圖示消失）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppActivation.release("borrow") }
    }

    /// 展開後檢查是否仍有圖示因空間不足被藏：提示（一次）；若使用者開啟「暫借選單列」則借位
    private func checkOverflowAfterExpand() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let s = self, !s.collapsed, !s.peeking, !s.editing else { return }
            let n = s.overflowHiddenCount()
            guard n > 0 else { return }
            Log.core.info("overflow: \(n) icons hidden by macOS after expand")
            if s.prefs.borrowOnExpand {
                s.borrowMenuBar()
            } else if !s.prefs.didShowOverflowTip {
                s.prefs.didShowOverflowTip = true
                Toast.show(L.toastOverflow.f(n), kind: .info, near: s.arrowScreenFrame)
            }
        }
    }

    /// 前景 App 選單列的右緣 x（AX；需輔助使用權限）
    private func frontAppMenuBarRightEdge() -> CGFloat? {
        guard AXPresser.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.3)
        var mb: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &mb) == .success,
              let mbAny = mb, CFGetTypeID(mbAny) == AXUIElementGetTypeID() else { return nil }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(mbAny as! AXUIElement, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kidsAny = kidsRef, CFGetTypeID(kidsAny) == CFArrayGetTypeID() else { return nil }
        let arr = kidsAny as! CFArray
        var maxX: CGFloat = 0
        for i in 0..<CFArrayGetCount(arr) {
            let item = unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self)
            var pos: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let p = pos, CFGetTypeID(p) == AXValueGetTypeID(),
                  let sz = size, CFGetTypeID(sz) == AXValueGetTypeID() else { continue }
            var pt = CGPoint.zero, sv = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sz as! AXValue, .cgSize, &sv)
            maxX = max(maxX, pt.x + sv.width)
        }
        return maxX > 0 ? maxX : nil
    }

    /// 預測展開後是否會撞到前景 App 的選單：隱藏圖示會從 ‹ 左側依序緊密排列，
    /// 用累計寬度推算目標（或最左圖示）展開後的 x，小於選單右緣就代表會被 macOS 藏起來。
    /// target 為 nil：一般展開（只有收合區會出現）；指定 target：代點或代為移動（含永久隱藏區）
    private func needsRoom(forTarget target: Int?) -> Bool {
        guard let boundary = arrowScreenMinX else { return false }
        // 左邊界 = 前景 App 選單右緣，或瀏海右緣（瀏海機型的圖示不能放在瀏海左邊）
        guard let right = [frontAppMenuBarRightEdge(), notchRightEdge(near: boundary)].compactMap({ $0 }).max() else { return false }
        let snap = snapshot()
        let left = snap.items
            .filter { target == nil ? $0.section == .hidden : $0.section != .shown }
            .sorted { $0.frame.minX > $1.frame.minX }   // 由右至左累計
        guard !left.isEmpty else { return false }
        var edge = boundary - (target == nil ? 17 : 25)  // 展開後 pusher（含邊距；移動時顯示分界線較寬）的左緣
        var predicted: CGFloat?
        var passedSep = false
        for it in left {
            if it.section == .alwaysHidden, !passedSep { edge -= 26; passedSep = true } // 展開的永久隱藏分隔線
            edge -= it.frame.width
            if target == nil || it.windowID == target { predicted = edge; if target != nil { break } }
        }
        guard let x = predicted else { return false }
        let need = x < right + 6
        Log.core.info("needsRoom target=\(target ?? -1) predictedX=\(Int(x)) menuRight=\(Int(right)) → \(need)")
        return need
    }

    private func notchRightEdge(near x: CGFloat) -> CGFloat? {
        guard #available(macOS 12.0, *),
              let s = NSScreen.screens.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }),
              let area = s.auxiliaryTopRightArea else { return nil }
        return area.minX >= s.frame.minX ? area.minX : s.frame.minX + area.minX
    }

    /// ‹ 左側、座標在畫面內、卻未真正顯示的第三方狀態列視窗數
    private func overflowHiddenCount() -> Int {
        snapshot(details: false).items.filter {
            $0.section != .shown && !$0.onScreen && $0.frame.minX >= 0 && ScreenGeometry.xOnSomeScreen($0.frame.midX)
        }.count
    }

    // MARK: - 自動收合

    private func scheduleCollapse(after override: TimeInterval? = nil) {
        cancelTimer()
        let base = TimeInterval(prefs.autoCollapseSeconds)
        let interval: TimeInterval
        if let o = override {
            interval = o
        } else {
            switch expandReason {
            case .hover:   interval = base == 0 ? 4 : min(max(base, 3), 6)
            case .forward: interval = 1.2
            default:       interval = base
            }
        }
        guard interval > 0 else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.attemptCollapse()
        }
    }

    private func attemptCollapse() {
        guard !collapsed, !peeking, !editing else { return }
        let busy = forwardPending || boundaryVisible || isStatusItemUIOpen
            || NSEvent.modifierFlags.contains(.command) || mouseInMenuBar
        Log.core.debug("attemptCollapse busy=\(busy)")
        if busy {
            scheduleCollapse(after: expandReason == .forward ? 0.6 : 1.5) // 稍後再試，一有空就收
        } else {
            setCollapsed(true)
        }
    }

    private func cancelTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    private var mouseInMenuBar: Bool { ScreenGeometry.pointInMenuBar(NSEvent.mouseLocation) }

    /// 有任何選單、或貼在選單列下方的彈出視窗開著（使用者正在跟某個狀態列圖示互動）
    var isStatusItemUIOpen: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let anchoredLevels: Set<Int> = [Int(CGWindowLevelForKey(.floatingWindow)),
                                        Int(CGWindowLevelForKey(.statusWindow)),
                                        Int(CGWindowLevelForKey(.modalPanelWindow))]
        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        let bands = ScreenGeometry.menuBarBottomBandsCG()
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer > 0,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd),
                  r.width >= 40, r.height >= 24 else { continue }
            if layer == menuLevel { return true }                       // 任何選單（含我們自己的）
            guard (w[kCGWindowOwnerPID as String] as? Int) != myPid else { continue } // 我們的面板／提示不算
            if anchoredLevels.contains(layer), r.height > 40,
               bands.contains(where: { $0.contains(r.minY) }) { return true }
        }
        return false
    }

    // MARK: - 點擊他處即收合

    private func updateClickAwayMonitor() {
        let want = !collapsed && !peeking && !editing && prefs.clickAwayCollapse
        if want, clickAwayMonitor == nil {
            clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.handleGlobalClick()
            }
        } else if !want, let m = clickAwayMonitor {
            NSEvent.removeMonitor(m)
            clickAwayMonitor = nil
        }
    }

    private func handleGlobalClick() {
        guard !collapsed, !peeking, !editing, !forwardPending else { return }
        guard Date().timeIntervalSince(lastForwardTime) > 1.5 else { return }
        guard !mouseInMenuBar, !NSEvent.modifierFlags.contains(.command) else { return }
        let hadUI = isStatusItemUIOpen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let s = self, !s.collapsed, !s.peeking, !s.editing else { return }
            if s.isStatusItemUIOpen { return }             // 選單還開著（例如點進子選單）
            if hadUI { s.scheduleCollapse(after: 0.8) }    // 剛關掉一個選單 → 稍後收
            else { s.setCollapsed(true) }                  // 純粹點到別處 → 立即收
        }
    }

    // MARK: - ⌘ 拖曳整理時顯示分界線

    private func installDragMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in self?.dragTick() }) {
            dragMonitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in self?.dragEnded() }) {
            dragMonitors.append(m)
        }
        // 拖曳的是我們自己的 ‹ 時，事件送到本 App，只有本地監聽收得到
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] e in self?.dragTick(); return e }) {
            localDragMonitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] e in self?.dragEnded(); return e }) {
            localDragMonitors.append(m)
        }
    }

    private func dragTick() {
        guard !editing, !ItemMover.isMoving, NSEvent.modifierFlags.contains(.command), mouseInMenuBar else { return }
        arranging = true
        guard prefs.showBoundaryWhileArranging, !collapsed, !boundaryVisible else { return }
        boundaryVisible = true
        cancelTimer()
        apply()
    }

    private func dragEnded() {
        if arranging {
            arranging = false
            lastUserArrange = Date()
            // 使用者自己 ⌘ 拖曳完：記下他換了區塊的圖示（不然自動歸位會把它拉回去）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.rememberUserArrangement() }
        }
        guard boundaryVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let s = self, s.boundaryVisible else { return }
            s.boundaryVisible = false
            s.apply()
            s.scheduleCollapse()
        }
    }

    // MARK: - 一次性提示

    private func maybeShowCollapseHint() {
        guard !(prefs.didShowHideTip && prefs.didShowEmptyTip) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let s = self, s.collapsed else { return }
            let n = s.snapshot(details: false).items.filter { $0.section != .shown }.count
            if n == 0, !s.prefs.didShowEmptyTip {
                s.prefs.didShowEmptyTip = true
                Toast.show(L.toastNothingHidden.s, kind: .info, near: s.arrowScreenFrame)
            } else if n > 0, !s.prefs.didShowHideTip {
                s.prefs.didShowHideTip = true
                Toast.show(L.toastHiddenCount.f(n), kind: .success, near: s.arrowScreenFrame)
            }
        }
    }

    // MARK: - 點擊 / 懸停

    @objc private func toggleClicked(_ sender: Any?) {
        hoverWork?.cancel()
        SystemMonitor.shared.noteUserActivity()
        guard let ev = NSApp.currentEvent else { activate(); return }
        if ev.type == .rightMouseUp || ev.modifierFlags.contains(.control) {
            showMenu(); return
        }
        if ev.modifierFlags.contains(.option) {
            toggleAlwaysRevealed(); return
        }
        activate()
    }

    // NSTrackingArea 呼叫的是 Objective-C 選擇器 mouseEntered: / mouseExited:，必須明確標註
    @objc(mouseEntered:) func mouseEntered(_ event: NSEvent) {
        Log.core.info("mouseEntered hover=\(self.prefs.hoverToExpand) collapsed=\(self.collapsed)")
        guard prefs.hoverToExpand, toggleItem.menu == nil, !editing else { return }
        hoverWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self, s.prefs.hoverToExpand, !s.editing else { return }
            // 觸發當下再確認滑鼠真的還停在 ‹ 上：路過不誤觸，也不受 AppKit 偶發的瞬間 exit 雜訊影響
            guard let f = s.arrowScreenFrame, f.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
            SystemMonitor.shared.noteUserActivity()
            if s.prefs.isFloatMode {
                if !s.floatBar.isOpen, s.collapsed { s.floatBar.open(byHover: true) }
            } else if s.collapsed {
                s.setCollapsed(false, reason: .hover)
            }
        }
        hoverWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w) // 短暫停留才算懸停
    }

    @objc(mouseExited:) func mouseExited(_ event: NSEvent) {
        Log.core.info("mouseExited")
        // 不在此取消 hoverWork（由觸發時的位置檢查決定）；只負責安排收合
        if !collapsed, expandReason == .hover, !editing { scheduleCollapse(after: 2.0) }
    }

    // MARK: - 右鍵選單

    private func showMenu() {
        let m = NSMenu()
        m.delegate = self
        m.addItem(mi(collapsed ? L.menuShow.s : L.menuHide.s, #selector(menuToggle), symbol: collapsed ? "eye" : "eye.slash"))
        m.addItem(mi(L.menuFloatPanel.s, #selector(menuFloat), symbol: "square.grid.3x2"))
        m.addItem(mi(L.menuPeek.s, #selector(menuPeek), symbol: "sparkle.magnifyingglass"))
        if prefs.alwaysHiddenEnabled {
            m.addItem(mi(alwaysRevealed ? L.menuHideAlways.s : L.menuRevealAlways.s, #selector(menuAlways), symbol: "eye.trianglebadge.exclamationmark"))
        }
        m.addItem(.separator())
        m.addItem(mi(L.menuArrange.s, #selector(menuArrange), symbol: "square.grid.3x1.below.line.grid.1x2"))
        let fm = mi(L.menuFloatMode.s, #selector(menuToggleFloatMode))
        fm.state = prefs.isFloatMode ? .on : .off
        m.addItem(fm)
        let li = mi(L.menuLoginItem.s, #selector(menuToggleLogin))
        li.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(li)
        m.addItem(.separator())
        m.addItem(mi(L.menuHowTo.s, #selector(menuHowTo)))
        if UpdaterManager.shared.available {
            m.addItem(mi(L.menuCheckUpdates.s, #selector(menuUpdates)))
        }
        m.addItem(mi(L.menuSettings.s, #selector(menuSettings), key: ","))
        m.addItem(.separator())
        m.addItem(mi(L.menuQuit.s, #selector(menuQuit), key: "q"))
        menuOpen = true
        toggleItem.menu = m
        toggleItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        DispatchQueue.main.async { [weak self] in self?.toggleItem.menu = nil }
    }

    private func mi(_ title: String, _ sel: Selector, symbol: String? = nil, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuFloat() { floatBar.toggle() }
    @objc private func menuPeek() { peek() }
    @objc private func menuAlways() { toggleAlwaysRevealed() }
    @objc private func menuArrange() { NotificationCenter.default.post(name: .bbShowLayout, object: nil) }
    @objc private func menuHowTo() { NotificationCenter.default.post(name: .bbShowOnboarding, object: nil) }
    @objc private func menuUpdates() { UpdaterManager.shared.checkForUpdates() }
    @objc private func menuSettings() { NotificationCenter.default.post(name: .bbShowSettings, object: nil) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleFloatMode() {
        prefs.clickMode = prefs.isFloatMode ? "menubar" : "float"
        let nowFloat = prefs.clickMode == "float"
        Toast.show(nowFloat ? L.toastModeFloat.s : L.toastModeMenubar.s, kind: .info, near: arrowScreenFrame)
    }

    @objc private func menuToggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Toast.show(L.toastLoginOff.s, kind: .info, near: arrowScreenFrame)
            } else {
                try SMAppService.mainApp.register()
                Toast.show(L.toastLoginOn.s, kind: .success, near: arrowScreenFrame)
            }
        } catch {
            Toast.show("\(L.alertLoginFail.s): \(error.localizedDescription)", kind: .warning, near: arrowScreenFrame)
        }
    }

    // MARK: - 重設位置

    func resetPositions() {
        let d = UserDefaults.standard
        for name in ["BB_Toggle", "BB_HideSep", "BB_Pusher", "BB_AlwaysSep"] {
            d.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
            d.removeObject(forKey: "NSStatusItem Visible \(name)")
        }
        d.removeObject(forKey: Self.backupKey)
        d.set(1.0, forKey: "NSStatusItem Preferred Position BB_Toggle")
        d.set(false, forKey: "collapsed")
        d.synchronize()
    }

    // MARK: - 圖片

    private static func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "BarButler")
        return img?.withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
    }

    private static func separatorImage(alpha: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 9, height: 18), flipped: false) { rect in
            let line = NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 2, width: 1.5, height: rect.height - 4),
                                    xRadius: 0.75, yRadius: 0.75)
            NSColor.black.withAlphaComponent(alpha).setFill()
            line.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

extension BarSnapshot {
    /// ‹ 與 pusher 都真的顯示在畫面上（沒被前景 App 的選單擠掉）
    var anchorsVisible: Bool { anchors?.toggleOnScreen == true }
}

import AppKit
import Combine
import ServiceManagement

/// 展開的原因 → 決定自動收合的節奏
enum ExpandReason { case click, hover, forward, peek, other }

enum IconStyleKit {
    static func symbolName(style: String, collapsed: Bool) -> String {
        switch style {
        case "dots":   return collapsed ? "ellipsis.circle.fill" : "ellipsis.circle"
        case "arrows": return collapsed ? "arrow.right.to.line.compact" : "arrow.left.to.line.compact"
        default:       return collapsed ? "chevron.right" : "chevron.left"
        }
    }
}

/// 核心：使用者看得到的只有一個 ‹（toggle）。
///   [永久隱藏區…] ▏alwaysSep（選用）  [要收合的圖示…]  ▏pusher（1px 隱形）  ‹ toggle  [永遠顯示…]
/// 收合時把 pusher 的 length 撐到 10000，把它左邊的圖示全部擠出畫面。
/// pusher 永遠自動黏在 ‹ 左側、無圖示、不可點擊——單圖示外觀 + 穩定機制。
final class StatusBarController: NSObject, NSMenuDelegate {
    static let toggleWidth: CGFloat = 24
    static let pusherIdle: CGFloat = 1
    static let pusherBoundary: CGFloat = 9
    static let sepWidth: CGFloat = 10
    static let hugeWidth: CGFloat = 10000

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
    private var peeking = false
    private var alwaysRevealed = false
    private var expandReason: ExpandReason = .other
    private var isAdjusting = false
    private var validateWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var boundaryVisible = false
    private var clickAwayMonitor: Any?
    private var dragMonitors: [Any] = []
    private var forwardPending = false
    private var lastForwardTime = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    private(set) var collapsed: Bool

    /// ‹ 在螢幕上的位置（NSScreen 座標；x 軸與 CGWindow 全域座標一致）
    var arrowScreenFrame: NSRect? { toggleItem.button?.window?.frame }
    var arrowScreenMinX: CGFloat? { arrowScreenFrame?.minX }

    override init() {
        collapsed = prefs.collapsed
        super.init()

        migratePositionSchema()
        buildItems()
        apply()
        observePositionDefaults()
        installDragMonitors()

        // 啟動後複查一次 pusher 是否貼緊 ‹（等版面穩定再驗）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let s = self, !s.collapsed else { return }
            s.syncPusher()
        }

        let reapply: (Any) -> Void = { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
        prefs.$alwaysHiddenEnabled.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$language.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$iconStyle.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$clickAwayCollapse.dropFirst().sink(receiveValue: reapply).store(in: &cancellables)
        prefs.$clickMode.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.floatBar.close(); self?.apply() } }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refreshAfterWake() }
    }

    // MARK: - 位置鍵

    private static func posKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// 距右端距離，越小越靠右；nil = 尚未有紀錄
    private func position(_ name: String) -> Double? {
        (UserDefaults.standard.object(forKey: Self.posKey(name)) as? NSNumber)?.doubleValue
    }

    /// v1.1.1 起採用 pusher 架構：清除舊紀錄並把 ‹ 放到最右側
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
            d.set(1.0, forKey: Self.posKey("BB_Toggle"))
        }
    }

    // MARK: - 建立狀態列項目

    private func buildItems() {
        isAdjusting = true
        defer { DispatchQueue.main.async { [weak self] in self?.isAdjusting = false } }

        toggleItem = bar.statusItem(withLength: Self.toggleWidth)
        toggleItem.autosaveName = "BB_Toggle"
        toggleItem.isVisible = true
        if let b = toggleItem.button {
            b.target = self
            b.action = #selector(toggleClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.setAccessibilityLabel("BarButler")
            b.addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        buildPusher()

        alwaysSep = bar.statusItem(withLength: Self.hugeWidth)
        alwaysSep.autosaveName = "BB_AlwaysSep"
    }

    /// pusher 永遠黏在 ‹ 左側（位置值 = ‹ + 0.5）
    private func buildPusher() {
        if let p = pusher { bar.removeStatusItem(p) }
        let d = UserDefaults.standard
        let anchor = position("BB_Toggle") ?? toggleGeometryDistance ?? 1.0
        d.set(anchor + 0.5, forKey: Self.posKey("BB_Pusher"))
        pusher = bar.statusItem(withLength: collapsed ? Self.hugeWidth : Self.pusherIdle)
        pusher.autosaveName = "BB_Pusher"
        pusher.isVisible = true
        pusher.button?.isEnabled = false // 不可點擊、無圖示 → 使用者感知不到它
    }

    /// 以幾何位置換算 ‹ 的「距右端距離」（與 Preferred Position 同座標系）
    private var toggleGeometryDistance: Double? {
        guard let w = toggleItem?.button?.window,
              let screen = w.screen ?? NSScreen.main else { return nil }
        return Double(screen.frame.maxX - w.frame.minX)
    }

    /// 真相來源：pusher 必須在 ‹「左側」且緊貼（方向性檢查，避免 ‹ 被拖到 pusher 左邊而不知）
    private var pusherAdjacent: Bool {
        guard let tw = toggleItem.button?.window,
              let pw = pusher.button?.window else { return false }
        let gap = tw.frame.minX - pw.frame.maxX
        return gap >= -2 && gap <= 30
    }

    /// 確保 pusher 就位後再執行後續動作（收合前必經）
    private func syncPusher(then completion: (() -> Void)? = nil) {
        guard !collapsed else { completion?(); return }
        if pusherAdjacent { completion?(); return }
        isAdjusting = true
        buildPusher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let s = self else { return }
            if !s.pusherAdjacent, let g = s.toggleGeometryDistance {
                UserDefaults.standard.set(g + 0.5, forKey: Self.posKey("BB_Pusher"))
                s.buildPusher()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                s.isAdjusting = false
                s.apply()
                completion?()
            }
        }
    }

    private func rebuildItems() {
        bar.removeStatusItem(toggleItem)
        if let p = pusher { bar.removeStatusItem(p) }
        bar.removeStatusItem(alwaysSep)
        pusher = nil
        buildItems()
        apply()
    }

    // MARK: - 位置守衛

    private func observePositionDefaults() {
        for n in ["BB_Toggle", "BB_Pusher", "BB_AlwaysSep"] {
            UserDefaults.standard.addObserver(self, forKeyPath: Self.posKey(n), options: [.new], context: nil)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath?.hasPrefix("NSStatusItem Preferred Position") == true else { return }
        guard !isAdjusting else { return }
        validateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.validatePositions() }
        validateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func validatePositions() {
        guard !isAdjusting, !collapsed else { return } // 收合中版面浮動，不校正
        if !pusherAdjacent {                         // 使用者拖動了 ‹ → pusher 自動跟上
            syncPusher()
            return
        }
        // 永久隱藏區分隔線必須在 ‹ 左側
        if prefs.alwaysHiddenEnabled, alwaysSep.isVisible,
           let tw = toggleItem.button?.window, let aw = alwaysSep.button?.window,
           aw.frame.minX > tw.frame.minX {
            healAlwaysSep()
        }
    }

    /// 只修永久隱藏區分隔線：移到 ‹ 左側，不動 ‹ 的位置
    private func healAlwaysSep() {
        guard !isAdjusting else { return }
        isAdjusting = true
        bar.removeStatusItem(alwaysSep)
        UserDefaults.standard.set((position("BB_Toggle") ?? 1.0) + 80, forKey: Self.posKey("BB_AlwaysSep"))
        alwaysSep = bar.statusItem(withLength: Self.hugeWidth)
        alwaysSep.autosaveName = "BB_AlwaysSep"
        apply()
        Toast.show(L.toastFixed.s, kind: .info, near: arrowScreenFrame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.isAdjusting = false }
    }

    /// 大修復：‹ 被擠出畫面 → 清掉所有位置紀錄重排（‹ 回最右側），展開並提示
    private func heal() {
        guard !isAdjusting else { return }
        Log.core.error("‹ off-screen → heal")
        isAdjusting = true
        let d = UserDefaults.standard
        for n in ["BB_Toggle", "BB_Pusher", "BB_AlwaysSep"] {
            d.removeObject(forKey: Self.posKey(n))
            d.removeObject(forKey: "NSStatusItem Visible \(n)")
        }
        d.set(1.0, forKey: Self.posKey("BB_Toggle"))
        rebuildItems()
        reallySetCollapsed(false, reason: .other)
        Toast.show(L.toastHealed.s, kind: .warning, near: arrowScreenFrame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.isAdjusting = false }
    }

    /// 收合後確認 ‹ 仍在畫面上（雙保險），不在就修復
    private func scheduleOffscreenCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let s = self, s.collapsed, !s.isAdjusting else { return }
            guard let w = s.toggleItem.button?.window else { return }
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(w.frame) }
            if !onScreen { s.heal() }
        }
    }

    // MARK: - 狀態套用

    private func apply() {
        if let b = toggleItem.button {
            b.image = Self.symbol(IconStyleKit.symbolName(style: prefs.iconStyle, collapsed: collapsed))
            let tip = prefs.isFloatMode ? L.tooltipFloat.s : L.tooltipMenubar.s
            if b.toolTip != tip { b.toolTip = tip }
        }
        if collapsed {
            pusher.length = Self.hugeWidth
            pusher.button?.image = nil
            scheduleOffscreenCheck()
        } else if boundaryVisible {
            pusher.length = Self.pusherBoundary
            pusher.button?.image = Self.separatorImage(alpha: 0.6)
        } else {
            pusher.length = Self.pusherIdle
            pusher.button?.image = nil
        }

        let alwaysOn = prefs.alwaysHiddenEnabled
        alwaysSep.isVisible = alwaysOn
        if alwaysOn {
            let show = (alwaysRevealed || peeking) && !collapsed
            alwaysSep.length = show ? Self.sepWidth : Self.hugeWidth
            alwaysSep.button?.image = show ? Self.separatorImage(alpha: 0.5) : nil
        }
        updateClickAwayMonitor()
    }

    func refreshAfterWake() {
        apply()
        if !collapsed { syncPusher() }
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
        collapsed = c
        prefs.collapsed = c
        if c {
            alwaysRevealed = false
            boundaryVisible = false
            expandReason = .other
            cancelTimer()
            apply()
            maybeShowCollapseHint()
        } else {
            expandReason = reason
            apply()
            scheduleCollapse()
        }
    }

    func toggle() { setCollapsed(!collapsed, reason: .click) }
    func hide() { if !collapsed { setCollapsed(true) } }
    func show() { if collapsed { setCollapsed(false, reason: .click) } }

    /// 主要進入點（左鍵／快捷鍵）：依使用者選擇的模式行動
    func activate() {
        Log.core.info("activate float=\(self.prefs.isFloatMode) collapsed=\(self.collapsed)")
        if prefs.isFloatMode {
            if !collapsed && !floatBar.isOpen { setCollapsed(true) } // 已展開時點 ‹ = 收合
            else { floatBar.toggle() }
        } else {
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
        guard !peeking else { return }
        peeking = true
        let restoreCollapsed = collapsed
        let restoreRevealed = alwaysRevealed
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

    // MARK: - 面板代點（FloatBar 呼叫）

    func beginForward() {
        lastForwardTime = Date()
        forwardPending = true
        if collapsed { setCollapsed(false, reason: .forward) } else { expandReason = .forward }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.endForward() } // 安全網
    }

    func endForward() {
        guard forwardPending else { return }
        forwardPending = false
        if !collapsed { scheduleCollapse(after: 1.0) }
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
        guard !collapsed, !peeking else { return }
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
        let want = !collapsed && !peeking && prefs.clickAwayCollapse
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
        guard !collapsed, !peeking, !forwardPending else { return }
        guard Date().timeIntervalSince(lastForwardTime) > 1.5 else { return }
        guard !mouseInMenuBar, !NSEvent.modifierFlags.contains(.command) else { return }
        let hadUI = isStatusItemUIOpen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let s = self, !s.collapsed, !s.peeking else { return }
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
    }

    private func dragTick() {
        guard prefs.showBoundaryWhileArranging, !collapsed, !boundaryVisible else { return }
        guard NSEvent.modifierFlags.contains(.command), mouseInMenuBar else { return }
        boundaryVisible = true
        cancelTimer()
        apply()
    }

    private func dragEnded() {
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
            let n = HiddenItemScanner.scan(leftOf: s.arrowScreenMinX ?? .greatestFiniteMagnitude).count
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
        guard prefs.hoverToExpand, toggleItem.menu == nil else { return }
        hoverWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self, s.prefs.hoverToExpand else { return }
            // 觸發當下再確認滑鼠真的還停在 ‹ 上：路過不誤觸，也不受 AppKit 偶發的瞬間 exit 雜訊影響
            guard let f = s.arrowScreenFrame, f.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
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
        if !collapsed, expandReason == .hover { scheduleCollapse(after: 2.0) }
    }

    // MARK: - 右鍵選單

    private func showMenu() {
        let m = NSMenu()
        m.delegate = self
        m.addItem(mi(collapsed ? L.menuShow.s : L.menuHide.s, #selector(menuToggle)))
        m.addItem(mi(L.menuFloatPanel.s, #selector(menuFloat)))
        m.addItem(mi(L.menuPeek.s, #selector(menuPeek)))
        if prefs.alwaysHiddenEnabled {
            m.addItem(mi(alwaysRevealed ? L.menuHideAlways.s : L.menuRevealAlways.s, #selector(menuAlways)))
        }
        m.addItem(.separator())
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
        m.addItem(mi(L.menuSettings.s, #selector(menuSettings)))
        m.addItem(.separator())
        m.addItem(mi(L.menuQuit.s, #selector(menuQuit)))
        toggleItem.menu = m
        toggleItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in self?.toggleItem.menu = nil }
    }

    private func mi(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuFloat() { floatBar.toggle() }
    @objc private func menuPeek() { peek() }
    @objc private func menuAlways() { toggleAlwaysRevealed() }
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

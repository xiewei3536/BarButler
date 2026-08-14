import AppKit
import Combine

/// 核心：使用者看得到的只有一個 ‹（toggle）。
///   [永久隱藏區…] ▏alwaysSep（選用）  [要收合的圖示…]  ▏pusher（1px 隱形）  ‹ toggle  [永遠顯示…]
/// 收合時把 pusher 的 length 撐到 10000，把它左邊的圖示全部擠出畫面（v1.0 驗證過的機制）。
/// pusher 永遠自動黏在 ‹ 左側、無圖示、不可點擊、1px 寬幾乎不可能被拖到——單圖示外觀 + 穩定機制。
final class StatusBarController: NSObject, NSMenuDelegate {
    static let toggleWidth: CGFloat = 24
    static let pusherIdle: CGFloat = 1
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
    private var hoverDidExpand = false
    private var isAdjusting = false
    private var validateWork: DispatchWorkItem?
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
        refreshLocalization()
        observePositionDefaults()
        // 啟動後複查一次 pusher 是否貼緊 ‹（等版面穩定再驗）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let s = self, !s.collapsed else { return }
            s.syncPusher()
        }

        prefs.$alwaysHiddenEnabled.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
            .store(in: &cancellables)
        prefs.$language.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshLocalization() } }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.apply() }
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
        // ‹ 預設在最右側（緊鄰系統圖示），不會被 macOS 的空間不足機制擠掉
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

    /// 真相來源：用視窗實際位置判斷 pusher 是否緊貼 ‹ 左側
    private var pusherAdjacent: Bool {
        guard let tw = toggleItem.button?.window,
              let pw = pusher.button?.window else { return false }
        return abs(pw.frame.maxX - tw.frame.minX) <= 30
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
                // 位置紀錄不可信時退回幾何換算，再試一次
                UserDefaults.standard.set(g + 0.5, forKey: Self.posKey("BB_Pusher"))
                s.buildPusher()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                s.isAdjusting = false
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
        refreshLocalization()
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
        // 使用者拖動 ‹ 後，pusher 自動跟上（以實際幾何位置為準）
        if !pusherAdjacent {
            syncPusher { [weak self] in self?.apply() }
            return
        }
        // 永久隱藏區分隔線必須在 ‹（含 pusher）左側
        if prefs.alwaysHiddenEnabled,
           let t = position("BB_Toggle"),
           let a = position("BB_AlwaysSep"), a <= t + 0.5 {
            heal()
        }
    }

    /// 大修復：清掉所有位置紀錄重排（‹ 回最右側），展開並提示
    private func heal() {
        guard !isAdjusting else { return }
        isAdjusting = true
        let d = UserDefaults.standard
        for n in ["BB_Toggle", "BB_Pusher", "BB_AlwaysSep"] {
            d.removeObject(forKey: Self.posKey(n))
            d.removeObject(forKey: "NSStatusItem Visible \(n)")
        }
        d.set(1.0, forKey: Self.posKey("BB_Toggle"))
        rebuildItems()
        setCollapsed(false)
        Toast.show(L.toastFixed.s)
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
        toggleItem.button?.image = Self.symbol(collapsed ? "chevron.right" : "chevron.left")
        pusher.length = collapsed ? Self.hugeWidth : Self.pusherIdle
        if collapsed { scheduleOffscreenCheck() }

        let alwaysOn = prefs.alwaysHiddenEnabled
        alwaysSep.isVisible = alwaysOn
        if alwaysOn {
            let show = (alwaysRevealed || peeking) && !collapsed
            alwaysSep.length = show ? Self.sepWidth : Self.hugeWidth
            alwaysSep.button?.image = show ? Self.separatorImage(alpha: 0.5) : nil
        }
    }

    func refreshLocalization() {
        toggleItem.button?.toolTip = L.tooltip.s
    }

    // MARK: - 收合／展開

    func setCollapsed(_ c: Bool, byHover: Bool = false) {
        // 收合前先確保 pusher 貼緊 ‹，才會把正確的區塊藏起來
        if c, !collapsed, !pusherAdjacent {
            syncPusher { [weak self] in self?.reallySetCollapsed(true, byHover: byHover) }
            return
        }
        reallySetCollapsed(c, byHover: byHover)
    }

    private func reallySetCollapsed(_ c: Bool, byHover: Bool) {
        if peeking { peeking = false }
        collapsed = c
        prefs.collapsed = c
        if c {
            alwaysRevealed = false
            hoverDidExpand = false
            cancelTimer()
        } else {
            hoverDidExpand = byHover
            scheduleCollapse()
        }
        apply()
    }

    func toggle() { setCollapsed(!collapsed) }

    /// 主要進入點（左鍵／快捷鍵）：依使用者選擇的模式行動
    func activate() {
        if prefs.clickMode == "float" {
            floatBar.toggle()
        } else {
            toggle()
        }
    }

    private func toggleAlwaysRevealed() {
        guard prefs.alwaysHiddenEnabled else { toggle(); return }
        if collapsed {
            setCollapsed(false)
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
        cancelTimer()
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let s = self, s.peeking else { return }
            s.peeking = false
            s.collapsed = restoreCollapsed
            s.alwaysRevealed = restoreRevealed
            s.apply()
            if !s.collapsed { s.scheduleCollapse() }
        }
    }

    // MARK: - 自動收合

    private func scheduleCollapse(short: Bool = false) {
        cancelTimer()
        var interval = TimeInterval(prefs.autoCollapseSeconds)
        if hoverDidExpand { interval = short ? 2.5 : max(4, min(interval == 0 ? 6 : interval, 8)) }
        guard interval > 0 else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.attemptCollapse()
        }
    }

    private func attemptCollapse() {
        guard !collapsed else { return }
        if mouseInMenuBar || NSEvent.modifierFlags.contains(.command) {
            // 使用者還在選單列上或按著 ⌘ 整理圖示：每 2 秒快速重查，一離開就收
            cancelTimer()
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.attemptCollapse()
            }
        } else {
            setCollapsed(true)
        }
    }

    private func cancelTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    private var mouseInMenuBar: Bool {
        let loc = NSEvent.mouseLocation
        for s in NSScreen.screens {
            let f = s.frame
            if loc.x >= f.minX, loc.x <= f.maxX, loc.y >= f.maxY - 26, loc.y <= f.maxY { return true }
        }
        return false
    }

    // MARK: - 點擊 / 懸停

    @objc private func toggleClicked(_ sender: Any?) {
        guard let ev = NSApp.currentEvent else { activate(); return }
        if ev.type == .rightMouseUp || ev.modifierFlags.contains(.control) {
            showMenu(); return
        }
        if ev.modifierFlags.contains(.option) {
            toggleAlwaysRevealed(); return
        }
        activate()
    }

    @objc func mouseEntered(with event: NSEvent) {
        guard prefs.clickMode != "float" else { return } // 懸浮模式下懸停不動作
        if prefs.hoverToExpand, collapsed, toggleItem.menu == nil {
            setCollapsed(false, byHover: true)
        }
    }

    @objc func mouseExited(with event: NSEvent) {
        if hoverDidExpand, !collapsed { scheduleCollapse(short: true) }
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

    // MARK: - 重設位置

    func resetPositions() {
        let d = UserDefaults.standard
        for name in ["BB_Toggle", "BB_HideSep", "BB_Pusher", "BB_AlwaysSep"] {
            d.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
            d.removeObject(forKey: "NSStatusItem Visible \(name)")
        }
        d.set(1.0, forKey: "NSStatusItem Preferred Position BB_Toggle")
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

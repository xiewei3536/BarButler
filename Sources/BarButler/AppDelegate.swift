import AppKit
import Combine
import SwiftUI

/// 何時要當一般 App（Dock 有圖示、能取得選單列）：偏好設定／教學視窗開著、或暫借選單列騰空間
enum AppActivation {
    private static var reasons = Set<String>()

    static func require(_ r: String) { reasons.insert(r); update() }
    static func release(_ r: String) { reasons.remove(r); update() }

    private static func update() {
        let want: NSApplication.ActivationPolicy = reasons.isEmpty ? .accessory : .regular
        if NSApp.activationPolicy() != want { NSApp.setActivationPolicy(want) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let prefs = Prefs.shared
    private var statusController: StatusBarController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfDuplicate() else { return }   // 另一份正在執行：別再建一組同名的 ‹（會打亂位置）
        buildMainMenu()
        Log.event("launch \(version) pid=\(getpid())")

        SystemMonitor.shared.start()
        statusController = StatusBarController()
        _ = UpdaterManager.shared // 打包版啟用自動更新

        HotkeyManager.shared.onTrigger = { [weak self] in self?.statusController.activate() }
        Publishers.CombineLatest3(prefs.$hotkeyEnabled, prefs.$hotkeyKeyCode, prefs.$hotkeyModifiers)
            .sink { enabled, key, mods in
                HotkeyManager.shared.register(keyCode: key, modifiersRaw: mods, enabled: enabled)
            }
            .store(in: &cancellables)

        let nc = NotificationCenter.default
        nc.addObserver(forName: .bbPeek, object: nil, queue: .main) { [weak self] _ in
            self?.statusController.peek()
        }
        nc.addObserver(forName: .bbShowOnboarding, object: nil, queue: .main) { [weak self] _ in
            self?.showOnboarding()
        }
        nc.addObserver(forName: .bbShowSettings, object: nil, queue: .main) { [weak self] _ in
            self?.showSettings()
        }
        nc.addObserver(forName: .bbShowLayout, object: nil, queue: .main) { [weak self] _ in
            self?.showSettings(tab: .layout)
        }
        nc.addObserver(forName: .bbResetPositions, object: nil, queue: .main) { [weak self] _ in
            self?.statusController.resetPositions()
            self?.relaunch()
        }

        if !prefs.didOnboard {
            prefs.lastSeenVersion = version
            showOnboarding()
        } else if prefs.lastSeenVersion.compare("1.4", options: .numeric) == .orderedAscending {
            // 從 1.3 以前升級：介紹圖示配置（1.3 的喚醒錯誤可能已把配置弄亂）
            prefs.lastSeenVersion = version
            prefs.showWhatsNew = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.showSettings(tab: .layout) }
        } else if prefs.lastSeenVersion != version {
            prefs.lastSeenVersion = version
        }
    }

    /// 使用者在 Finder／啟動台再次開啟 App：打開偏好設定當作回饋
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - URL 自動化
    // barbutler://toggle | show | hide | peek | panel | settings | arrange | update | check | diagnose
    // barbutler://mode/float | mode/menubar | layout/hide-all | layout/show-all | remember
    // barbutler://move?item=<名稱或 App 或視窗編號>&to=shown|hidden|always
    // barbutler://click?item=<名稱>（代點隱藏的圖示、打開它的選單）

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "barbutler", let sc = statusController else { return }
        let cmd = (url.host ?? "").lowercased()
        let arg = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let query = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap { q in q.value.map { (q.name.lowercased(), $0) } } ?? [], uniquingKeysWith: { a, _ in a })
        Log.event("url: \(url.absoluteString)")
        switch cmd {
        case "toggle":               sc.toggle()
        case "show", "expand":       sc.show()
        case "hide", "collapse":     sc.hide()
        case "peek":                 sc.peek()
        case "panel":                sc.floatBar.toggle()
        case "settings":
            let tabs: [String: SettingsRouter.Tab] = ["layout": .layout, "general": .general, "advanced": .advanced, "about": .about]
            showSettings(tab: query["tab"].flatMap { tabs[$0.lowercased()] })
        case "arrange":              showSettings(tab: .layout)
        case "layout":
            switch arg {
            case "hide-all": sc.relocateToggle(rightEnd: true)
            case "show-all": sc.relocateToggle(rightEnd: false)
            default:         showSettings(tab: .layout)
            }
        case "update", "check-updates": UpdaterManager.shared.checkForUpdates()
        case "check":                sc.healthCheck("url")
        case "remember":             sc.rememberLayout("url")
        case "diagnose":             Diagnostics.write(name: query["file"] ?? "diagnostics.txt")
        case "move":                 moveFromURL(query, sc: sc)
        case "click", "open":        clickFromURL(query, sc: sc)
        case "mode":
            guard arg == "float" || arg == "menubar" else { return }
            prefs.clickMode = arg
            Toast.show(arg == "float" ? L.toastModeFloat.s : L.toastModeMenubar.s, kind: .info, near: sc.arrowScreenFrame)
        default: break
        }
    }

    private func findItem(_ key: String, in sc: StatusBarController) -> BarItem? {
        let items = sc.snapshot().items
        return items.first { String($0.windowID) == key }
            ?? items.first { $0.label.lowercased() == key }
            ?? items.first { $0.appName.lowercased() == key || $0.bundleID?.lowercased() == key }
            ?? items.first { $0.label.lowercased().contains(key) }
    }

    private func clickFromURL(_ q: [String: String], sc: StatusBarController) {
        guard let key = q["item"]?.lowercased() else { return }
        guard let item = findItem(key, in: sc) else {
            Toast.show(L.moveGone.f(key), kind: .warning, near: sc.arrowScreenFrame)
            return
        }
        sc.forwardClick(toWindow: item.windowID, name: item.label)
    }

    private func moveFromURL(_ q: [String: String], sc: StatusBarController) {
        guard let key = q["item"]?.lowercased(), let to = q["to"]?.lowercased() else { return }
        let dest: BarSection
        switch to {
        case "shown", "show", "visible": dest = .shown
        case "hidden", "hide": dest = .hidden
        case "always", "alwayshidden", "always-hidden": dest = .alwaysHidden
        default: return
        }
        guard let item = findItem(key, in: sc) else {
            Log.event("url move: no item matches \(key)")
            Toast.show(L.moveGone.f(key), kind: .warning, near: sc.arrowScreenFrame)
            return
        }
        sc.moveItem(item, to: dest)
    }

    // MARK: - 視窗

    func showSettings(tab: SettingsRouter.Tab? = nil) {
        if let tab { SettingsRouter.shared.tab = tab }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsRoot().environmentObject(prefs))
            settingsWindow = makeWindow(host, autosave: "BBSettingsWindow")
            settingsWindow?.identifier = NSUserInterfaceItemIdentifier("BBSettings")
        }
        present(settingsWindow, reason: "settings")
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView().environmentObject(prefs))
            onboardingWindow = makeWindow(host, autosave: nil)
        }
        present(onboardingWindow, reason: "onboarding")
    }

    func closeOnboarding() {
        prefs.didOnboard = true
        onboardingWindow?.close()
    }

    private func makeWindow(_ host: NSViewController, autosave: String?) -> NSWindow {
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.title = "BarButler"
        w.delegate = self
        if let autosave { w.setFrameAutosaveName(autosave) }
        w.center()
        return w
    }

    /// 視窗開著時當一般 App：選單列換成我們的短選單（騰出空間給圖示配置）、可用 ⌘Tab 切回
    private func present(_ w: NSWindow?, reason: String) {
        AppActivation.require(reason)
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        let reason = w == settingsWindow ? "settings" : w == onboardingWindow ? "onboarding" : nil
        guard let reason else { return }
        DispatchQueue.main.async { AppActivation.release(reason) }
    }

    // MARK: - 工具

    private func terminateIfDuplicate() -> Bool {
        guard let bid = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0 != NSRunningApplication.current }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }

    /// 等自己完全結束後再重新開啟（避免新舊實例同時存在而被去重邏輯砍掉）
    private func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { NSApp.terminate(nil); return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc private func openSettingsFromMenu() { showSettings() }

    /// 主選單：設定視窗開著時顯示在選單列（也讓 ⌘C/⌘V/⌘W/⌘Q 可用）
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: L.menuSettings.s, action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.menuQuit.s, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }
}

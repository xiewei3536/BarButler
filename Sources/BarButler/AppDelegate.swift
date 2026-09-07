import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Prefs.shared
    private var statusController: StatusBarController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateIfDuplicate()
        buildMainMenu()

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
        nc.addObserver(forName: .bbResetPositions, object: nil, queue: .main) { [weak self] _ in
            self?.statusController.resetPositions()
            self?.relaunch()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.statusController.refreshAfterWake() }
            }

        if !prefs.didOnboard {
            showOnboarding()
        }
    }

    /// 使用者在 Finder／啟動台再次開啟 App：打開偏好設定當作回饋
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - URL 自動化：barbutler://toggle | show | hide | peek | panel | settings | update | mode/float | mode/menubar

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "barbutler", let sc = statusController else { return }
        let cmd = (url.host ?? "").lowercased()
        let arg = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch cmd {
        case "toggle":               sc.toggle()
        case "show", "expand":       sc.show()
        case "hide", "collapse":     sc.hide()
        case "peek":                 sc.peek()
        case "panel":                sc.floatBar.toggle()
        case "settings":             showSettings()
        case "update", "check-updates": UpdaterManager.shared.checkForUpdates()
        case "mode":
            guard arg == "float" || arg == "menubar" else { return }
            prefs.clickMode = arg
            Toast.show(arg == "float" ? L.toastModeFloat.s : L.toastModeMenubar.s, kind: .info, near: sc.arrowScreenFrame)
        default: break
        }
    }

    // MARK: - 視窗

    func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsRoot().environmentObject(prefs))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.isRestorable = false
            w.title = "BarButler"
            w.setFrameAutosaveName("BBSettingsWindow")
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView().environmentObject(prefs))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.isRestorable = false
            w.title = "BarButler"
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func closeOnboarding() {
        prefs.didOnboard = true
        onboardingWindow?.close()
    }

    // MARK: - 工具

    private func terminateIfDuplicate() {
        guard let bid = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
        }
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

    /// 隱藏的主選單：讓 ⌘C/⌘V/⌘W/⌘Q 在設定視窗內可用
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit BarButler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

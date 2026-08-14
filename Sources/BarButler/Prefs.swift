import Foundation
import Combine

/// 偏好設定（UserDefaults 持久化）
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var language: String          { didSet { d.set(language, forKey: "language") } }
    @Published var autoCollapseSeconds: Int  { didSet { d.set(autoCollapseSeconds, forKey: "autoCollapseSeconds") } }
    @Published var hoverToExpand: Bool       { didSet { d.set(hoverToExpand, forKey: "hoverToExpand") } }
    @Published var clickMode: String         { didSet { d.set(clickMode, forKey: "clickMode") } } // "menubar" | "float"
    @Published var alwaysHiddenEnabled: Bool { didSet { d.set(alwaysHiddenEnabled, forKey: "alwaysHiddenEnabled") } }
    @Published var hotkeyEnabled: Bool       { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var hotkeyKeyCode: Int        { didSet { d.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    @Published var hotkeyModifiers: UInt     { didSet { d.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    @Published var didOnboard: Bool          { didSet { d.set(didOnboard, forKey: "didOnboard") } }
    @Published var collapsed: Bool           { didSet { d.set(collapsed, forKey: "collapsed") } }

    private init() {
        d.register(defaults: [
            "language": "auto",
            "autoCollapseSeconds": 10,
            "hoverToExpand": true,
            "clickMode": "menubar",
            "alwaysHiddenEnabled": false,
            "hotkeyEnabled": true,
            "hotkeyKeyCode": 11, // B
            "hotkeyModifiers": (1 << 20) | (1 << 19), // ⌘ + ⌥
            "didOnboard": false,
            "collapsed": false,
        ])
        language = d.string(forKey: "language") ?? "auto"
        autoCollapseSeconds = d.integer(forKey: "autoCollapseSeconds")
        hoverToExpand = d.bool(forKey: "hoverToExpand")
        clickMode = d.string(forKey: "clickMode") ?? "menubar"
        alwaysHiddenEnabled = d.bool(forKey: "alwaysHiddenEnabled")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        hotkeyKeyCode = d.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = UInt(bitPattern: d.integer(forKey: "hotkeyModifiers"))
        didOnboard = d.bool(forKey: "didOnboard")
        collapsed = d.bool(forKey: "collapsed")
    }
}

extension Notification.Name {
    static let bbPeek = Notification.Name("bb.peek")
    static let bbShowOnboarding = Notification.Name("bb.showOnboarding")
    static let bbResetPositions = Notification.Name("bb.resetPositions")
    static let bbShowSettings = Notification.Name("bb.showSettings")
}

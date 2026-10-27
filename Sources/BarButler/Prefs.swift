import Foundation
import Combine

/// 偏好設定（UserDefaults 持久化）
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var language: String              { didSet { d.set(language, forKey: "language") } }
    @Published var autoCollapseSeconds: Int      { didSet { d.set(autoCollapseSeconds, forKey: "autoCollapseSeconds") } }
    @Published var hoverToExpand: Bool           { didSet { d.set(hoverToExpand, forKey: "hoverToExpand") } }
    @Published var clickMode: String             { didSet { d.set(clickMode, forKey: "clickMode") } } // "menubar" | "float"
    @Published var iconStyle: String             { didSet { d.set(iconStyle, forKey: "iconStyle") } } // "chevron" | "dots" | "arrows"
    @Published var clickAwayCollapse: Bool       { didSet { d.set(clickAwayCollapse, forKey: "clickAwayCollapse") } }
    @Published var showBoundaryWhileArranging: Bool { didSet { d.set(showBoundaryWhileArranging, forKey: "showBoundaryWhileArranging") } }
    @Published var panelShowLabels: Bool         { didSet { d.set(panelShowLabels, forKey: "panelShowLabels") } }
    @Published var alwaysHiddenEnabled: Bool     { didSet { d.set(alwaysHiddenEnabled, forKey: "alwaysHiddenEnabled") } }
    @Published var hotkeyEnabled: Bool           { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var hotkeyKeyCode: Int            { didSet { d.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    @Published var hotkeyModifiers: UInt         { didSet { d.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    @Published var didOnboard: Bool              { didSet { d.set(didOnboard, forKey: "didOnboard") } }
    @Published var collapsed: Bool               { didSet { d.set(collapsed, forKey: "collapsed") } }
    @Published var didShowHideTip: Bool          { didSet { d.set(didShowHideTip, forKey: "didShowHideTip") } }
    @Published var didShowEmptyTip: Bool         { didSet { d.set(didShowEmptyTip, forKey: "didShowEmptyTip") } }
    @Published var didShowOverflowTip: Bool      { didSet { d.set(didShowOverflowTip, forKey: "didShowOverflowTip") } }
    @Published var borrowOnExpand: Bool          { didSet { d.set(borrowOnExpand, forKey: "borrowOnExpand") } }
    @Published var realIcons: Bool               { didSet { d.set(realIcons, forKey: "realIcons") } } // 圖示配置／面板顯示真實選單列圖示（需螢幕錄製）
    @Published var lastSeenVersion: String       { didSet { d.set(lastSeenVersion, forKey: "lastSeenVersion") } }
    @Published var showWhatsNew: Bool            { didSet { d.set(showWhatsNew, forKey: "showWhatsNew") } }
    @Published var rememberLayout: Bool          { didSet { d.set(rememberLayout, forKey: "rememberLayout") } } // 配置被打亂時自動歸位

    var isFloatMode: Bool { clickMode == "float" }

    private init() {
        d.register(defaults: [
            "language": "auto",
            "autoCollapseSeconds": 10,
            "hoverToExpand": true,
            "clickMode": "menubar",
            "iconStyle": "chevron",
            "clickAwayCollapse": true,
            "showBoundaryWhileArranging": true,
            "panelShowLabels": true,
            "alwaysHiddenEnabled": false,
            "hotkeyEnabled": true,
            "hotkeyKeyCode": 11, // B
            "hotkeyModifiers": (1 << 20) | (1 << 19), // ⌘ + ⌥
            "didOnboard": false,
            "collapsed": false,
            "didShowHideTip": false,
            "didShowEmptyTip": false,
            "didShowOverflowTip": false,
            "borrowOnExpand": false,
            "realIcons": false,
            "lastSeenVersion": "",
            "showWhatsNew": false,
            "rememberLayout": true,
        ])
        language = d.string(forKey: "language") ?? "auto"
        autoCollapseSeconds = d.integer(forKey: "autoCollapseSeconds")
        hoverToExpand = d.bool(forKey: "hoverToExpand")
        clickMode = d.string(forKey: "clickMode") ?? "menubar"
        iconStyle = d.string(forKey: "iconStyle") ?? "chevron"
        clickAwayCollapse = d.bool(forKey: "clickAwayCollapse")
        showBoundaryWhileArranging = d.bool(forKey: "showBoundaryWhileArranging")
        panelShowLabels = d.bool(forKey: "panelShowLabels")
        alwaysHiddenEnabled = d.bool(forKey: "alwaysHiddenEnabled")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        hotkeyKeyCode = d.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = UInt(bitPattern: d.integer(forKey: "hotkeyModifiers"))
        didOnboard = d.bool(forKey: "didOnboard")
        collapsed = d.bool(forKey: "collapsed")
        didShowHideTip = d.bool(forKey: "didShowHideTip")
        didShowEmptyTip = d.bool(forKey: "didShowEmptyTip")
        didShowOverflowTip = d.bool(forKey: "didShowOverflowTip")
        borrowOnExpand = d.bool(forKey: "borrowOnExpand")
        realIcons = d.bool(forKey: "realIcons")
        lastSeenVersion = d.string(forKey: "lastSeenVersion") ?? ""
        showWhatsNew = d.bool(forKey: "showWhatsNew")
        rememberLayout = d.bool(forKey: "rememberLayout")
    }
}

extension Notification.Name {
    static let bbPeek = Notification.Name("bb.peek")
    static let bbShowOnboarding = Notification.Name("bb.showOnboarding")
    static let bbResetPositions = Notification.Name("bb.resetPositions")
    static let bbShowSettings = Notification.Name("bb.showSettings")
    static let bbShowLayout = Notification.Name("bb.showLayout")
}

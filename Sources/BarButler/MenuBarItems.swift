import AppKit
import ApplicationServices

// MARK: - 螢幕幾何（CG 座標：原點在主螢幕左上、y 向下）

enum ScreenGeometry {
    private static var primary: NSScreen? { NSScreen.screens.first }

    /// 各螢幕選單列「頂邊」區間：狀態列圖示視窗的 minY 會落在這裡
    static func menuBarTopBandsCG() -> [ClosedRange<CGFloat>] {
        guard let main = primary else { return [] }
        return NSScreen.screens.map { s in
            let top = main.frame.maxY - s.frame.maxY
            return (top - 1)...(top + 8)
        }
    }

    /// 各螢幕選單列「底邊」區間：貼著選單列彈出的視窗 minY 會落在這裡
    static func menuBarBottomBandsCG() -> [ClosedRange<CGFloat>] {
        guard let main = primary else { return [] }
        return NSScreen.screens.map { s in
            let top = main.frame.maxY - s.frame.maxY
            let bottom = top + (s.frame.maxY - s.visibleFrame.maxY)
            return (bottom - 2)...(bottom + 14)
        }
    }

    /// NSScreen 座標的點是否落在某個螢幕的選單列上
    static func pointInMenuBar(_ p: NSPoint) -> Bool {
        NSScreen.screens.contains { s in
            p.x >= s.frame.minX && p.x <= s.frame.maxX && p.y >= s.visibleFrame.maxY - 2 && p.y <= s.frame.maxY
        }
    }

    /// x 是否落在某個螢幕的水平範圍內
    static func xOnSomeScreen(_ x: CGFloat) -> Bool {
        NSScreen.screens.contains { x >= $0.frame.minX && x <= $0.frame.maxX }
    }
}

// MARK: - 選單列項目模型

/// 三個區塊（由右至左）：常駐顯示｜收合區｜永久隱藏
enum BarSection: Int, CaseIterable, Identifiable {
    case shown, hidden, alwaysHidden
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .shown: return L.sectionShown.s
        case .hidden: return L.sectionHidden.s
        case .alwaysHidden: return L.sectionAlways.s
        }
    }
}

struct BarItem: Identifiable, Equatable {
    let windowID: Int
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let label: String
    let axIdentifier: String?
    let windowTitle: String?   // 狀態列項目的 autosave 名稱（需螢幕錄製權限才讀得到）
    let frame: CGRect      // CG 全域座標
    let onScreen: Bool     // macOS 因空間不足把它藏起來時為 false（座標仍可能在畫面內）
    let section: BarSection
    let movable: Bool
    /// 這次讀該 App 的輔助使用資訊失敗（逾時等）：識別不可靠，配置記憶不碰它
    var axUnavailable = false

    var id: Int { windowID }

    var appIcon: NSImage {
        NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// 系統項目（控制中心、輸入法…）的 App 圖示都一樣，改用對應的 SF Symbol
    var systemSymbol: String? {
        guard bundleID?.hasPrefix("com.apple.") == true else { return nil }
        let id = (axIdentifier ?? windowTitle ?? "").lowercased()
        let table: [(String, String)] = [
            ("battery", "battery.75"), ("wifi", "wifi"), ("bluetooth", "dot.radiowaves.left.and.right"),
            ("sound", "speaker.wave.2.fill"), ("display", "display"), ("focus", "moon.fill"),
            ("nowplaying", "play.circle.fill"), ("airdrop", "airplayaudio"), ("clock", "clock"),
            ("controlcenter", "switch.2"), ("spotlight", "magnifyingglass"), ("siri", "waveform.circle"),
            ("timemachine", "clock.arrow.circlepath"), ("vpn", "network.badge.shield.half.filled"),
            ("user", "person.crop.circle"), ("textinput", "keyboard"), ("keyboard", "keyboard"),
            ("screenmirroring", "rectangle.on.rectangle"), ("accessibility", "accessibility"),
            ("stagemanager", "square.stack.3d.down.right"), ("weather", "cloud.sun.fill"),
        ]
        for (k, sym) in table where id.contains(k) { return sym }
        if bundleID == "com.apple.TextInputMenuAgent" { return "keyboard" }
        return "circle.grid.2x2.fill"
    }

    static func == (a: BarItem, b: BarItem) -> Bool {
        a.windowID == b.windowID && a.section == b.section && a.frame == b.frame
            && a.onScreen == b.onScreen && a.label == b.label
    }
}

/// 我方三個狀態列項目的視窗位置（CG 座標）
struct BarAnchors {
    let toggleID: Int
    let toggle: CGRect
    let toggleOnScreen: Bool
    let pusherID: Int?
    let pusher: CGRect?
    let sepID: Int?
    let sep: CGRect?        // 永久隱藏分隔線（僅啟用時）
}

struct BarSnapshot {
    let anchors: BarAnchors?
    let items: [BarItem]    // 由左至右

    static let empty = BarSnapshot(anchors: nil, items: [])

    func items(in s: BarSection) -> [BarItem] { items.filter { $0.section == s } }
    func item(_ id: Int) -> BarItem? { items.first { $0.windowID == id } }

    /// 常駐區（含系統固定項目）＋ ‹ 佔用的寬度
    var shownWidth: CGFloat {
        items(in: .shown).reduce(0) { $0 + $1.frame.width } + (anchors?.toggle.width ?? 0)
    }

    var screenWidth: CGFloat {
        guard let t = anchors?.toggle else { return NSScreen.main?.frame.width ?? 1440 }
        return NSScreen.screens.first { $0.frame.minX <= t.midX && t.midX <= $0.frame.maxX }?.frame.width
            ?? NSScreen.main?.frame.width ?? 1440
    }
}

// MARK: - 掃描（CGWindowList 免權限；名稱、幽靈項目過濾用輔助使用 AX，有授權才用）

enum BarScanner {
    struct Own {
        let toggle: Int
        let pusher: Int?
        let sep: Int?       // nil = 永久隱藏區未啟用
    }

    private struct AXExtra {
        let frame: CGRect
        let identifier: String?
        let desc: String?
        let title: String?
    }

    private enum AXLookup {
        case items([AXExtra])
        case unsupported    // 該 App 沒有提供（無法判斷，照常處理）
        case failed         // 讀取失敗（逾時、App 卡住）
    }

    /// details = false 時只看位置（給移動時高頻輪詢用，不呼叫 AX）
    static func snapshot(own: Own?, details: Bool = true) -> BarSnapshot {
        guard let own,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return .empty }
        let myPid = Int(getpid())
        var ownFrames: [Int: (CGRect, Bool)] = [:]
        struct Raw { let id: Int; let pid: pid_t; let frame: CGRect; let on: Bool; let title: String?; let owner: String }
        var raws: [Raw] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 25,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd) else { continue }
            let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
            let on = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            if pid == myPid { ownFrames[num] = (r, on); continue }
            guard r.width >= 4, r.height >= 14, r.height <= 40 else { continue }
            if let a = w[kCGWindowAlpha as String] as? Double, a < 0.05 { continue }
            raws.append(Raw(id: num, pid: pid_t(pid), frame: r, on: on, title: w[kCGWindowName as String] as? String,
                            owner: w[kCGWindowOwnerName as String] as? String ?? "App"))
        }
        guard let (tf, ton) = ownFrames[own.toggle], tf.width > 0 else { return .empty }
        let pf = own.pusher.flatMap { ownFrames[$0]?.0 }
        let sf = own.sep.flatMap { ownFrames[$0]?.0 }.flatMap { $0.width > 0 ? $0 : nil }
        let anchors = BarAnchors(toggleID: own.toggle, toggle: tf, toggleOnScreen: ton,
                                 pusherID: own.pusher, pusher: pf, sepID: sf == nil ? nil : own.sep, sep: sf)

        // 只取 ‹ 所在那條選單列上的項目
        let band = (tf.minY - 4)...(tf.minY + 4)
        raws = raws.filter { band.contains($0.frame.minY) }

        // 被我方 pusher／分隔線「整個蓋住」的視窗是過期殘影（例如未顯示的系統模組）
        let ownSpans = [pf, sf].compactMap { $0 }.filter { $0.width > 100 }
        raws = raws.filter { r in !ownSpans.contains { $0.minX < r.frame.minX && r.frame.maxX < $0.maxX } }

        let useAX = details && AXPresser.trusted
        var extrasByPid: [pid_t: AXLookup] = [:]
        if useAX {
            for pid in Set(raws.map(\.pid)) { extrasByPid[pid] = axExtras(pid: pid) }
        }

        var items: [BarItem] = []
        var countByPid: [pid_t: Int] = [:]
        for r in raws { countByPid[r.pid, default: 0] += 1 }
        var appCache: [pid_t: NSRunningApplication?] = [:]
        for r in raws {
            var ax: AXExtra?
            var axFailed = false
            if useAX, case .items(let extras)? = extrasByPid[r.pid] {
                ax = extras.first { abs($0.frame.midX - r.frame.midX) <= max(6, r.frame.width / 2) }
                // App 有 AX 狀態列清單卻沒有對應項目 → 沒有真正顯示的幽靈視窗（例如關閉中的「專注模式」）
                if ax == nil { continue }
            } else {
                if useAX, case .failed? = extrasByPid[r.pid] { axFailed = true }
                if !r.on, raws.contains(where: { $0.id != r.id && $0.on && overlapRatio($0.frame, r.frame) > 0.4 }) {
                    continue // 無 AX 時：與真實項目重疊的未顯示視窗視為殘影
                }
            }
            let app = details ? (appCache[r.pid] ?? NSRunningApplication(processIdentifier: r.pid)) : nil
            if details { appCache[r.pid] = app }
            let bundle = app?.bundleIdentifier
            let appName = app?.localizedName ?? r.owner
            let label = makeLabel(appName: appName, bundle: bundle, ax: ax, multiple: (countByPid[r.pid] ?? 0) > 1)
            let section: BarSection
            if r.frame.midX > tf.midX { section = .shown }
            else if let s = sf, r.frame.midX < s.midX { section = .alwaysHidden }
            else { section = .hidden }
            let fixed = bundle == "com.apple.controlcenter"
                && (["com.apple.menuextra.clock", "com.apple.menuextra.controlcenter"].contains(ax?.identifier ?? "")
                    || ["Clock", "BentoBox"].contains(r.title ?? ""))
            var item = BarItem(windowID: r.id, pid: r.pid, bundleID: bundle, appName: appName, label: label,
                               axIdentifier: ax?.identifier, windowTitle: r.title, frame: r.frame, onScreen: r.on,
                               section: section, movable: !fixed)
            item.axUnavailable = axFailed
            items.append(item)
        }
        items.sort { $0.frame.minX < $1.frame.minX }
        return BarSnapshot(anchors: anchors, items: items)
    }

    private static func makeLabel(appName: String, bundle: String?, ax: AXExtra?, multiple: Bool) -> String {
        func clean(_ s: String?) -> String? {
            guard let s = s?.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces),
                  !s.isEmpty, s.count <= 24 else { return nil }
            return s
        }
        if bundle?.hasPrefix("com.apple.") == true, let d = clean(ax?.desc) ?? clean(ax?.title) { return d }
        if multiple, let d = clean(ax?.desc) ?? clean(ax?.title), d != appName { return "\(appName) · \(d)" }
        return appName
    }

    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let w = a.intersection(b).width
        return w <= 0 ? 0 : w / max(1, min(a.width, b.width))
    }

    /// 某 App 的 AXExtrasMenuBar 子項目
    private static func axExtras(pid: pid_t) -> AXLookup {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25) // 對方卡住時別拖累我們
        var mb: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &mb)
        guard err == .success, let m = mb, CFGetTypeID(m) == AXUIElementGetTypeID() else {
            switch err {
            case .attributeUnsupported, .noValue: return .unsupported
            default: return .failed
            }
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(m as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let arr = kids as? [AXUIElement] else { return .failed }
        return .items(arr.compactMap { el in
            var pos: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos) == .success,
                  AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size) == .success,
                  let p = pos, CFGetTypeID(p) == AXValueGetTypeID(),
                  let sz = size, CFGetTypeID(sz) == AXValueGetTypeID() else { return nil }
            var pt = CGPoint.zero, sv = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sz as! AXValue, .cgSize, &sv)
            func str(_ a: String) -> String? {
                var v: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success else { return nil }
                return v as? String
            }
            return AXExtra(frame: CGRect(origin: pt, size: sv), identifier: str("AXIdentifier"),
                           desc: str(kAXDescriptionAttribute), title: str(kAXTitleAttribute))
        })
    }
}

// MARK: - 真實圖示快取（需「螢幕錄製」權限；只擷取圖示本身那一小塊視窗）

final class IconCache {
    static let shared = IconCache()
    struct Glyph { let image: NSImage; let isLight: Bool }
    private var glyphs: [Int: Glyph] = [:]

    var permitted: Bool { CGPreflightScreenCaptureAccess() }
    var enabled: Bool { Prefs.shared.realIcons && permitted }

    func glyph(_ windowID: Int) -> Glyph? { enabled ? glyphs[windowID] : nil }

    /// CGWindowListCreateImage 在新版 SDK 標為不可用（要求改用 ScreenCaptureKit），但執行期仍可用且是唯一的同步做法；
    /// 以 dlsym 動態取得，避免日後 SDK 編譯失敗。找不到就退回 App 圖示。
    private typealias CreateImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImageFn? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CreateImageFn.self)
    }()

    /// 只有真的顯示在畫面上的項目擷取得到；藏起來的沿用先前擷取的結果
    func capture(_ items: [BarItem]) {
        guard enabled, let create = Self.createImage else { return }
        let opts = CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue
        for it in items where it.onScreen && ScreenGeometry.xOnSomeScreen(it.frame.midX) {
            guard let cg = create(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(it.windowID), opts)?
                    .takeRetainedValue(),
                  let light = Self.luminance(cg) else { continue }
            glyphs[it.windowID] = Glyph(image: NSImage(cgImage: cg, size: it.frame.size), isLight: light > 0.6)
        }
        let alive = Set(items.map(\.windowID))
        glyphs = glyphs.filter { alive.contains($0.key) }
    }

    /// 不透明像素的平均亮度；全透明（擷取失敗）回傳 nil
    private static func luminance(_ img: CGImage) -> CGFloat? {
        let w = 32, h = 16
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum: CGFloat = 0, n: CGFloat = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 128 {
            let a = CGFloat(px[i + 3]) / 255
            sum += (0.299 * CGFloat(px[i]) + 0.587 * CGFloat(px[i + 1]) + 0.114 * CGFloat(px[i + 2])) / 255 / a
            n += 1
        }
        return n < 3 ? nil : sum / n
    }
}

// MARK: - 輔助使用（點擊轉發、移動圖示都需要）

enum AXPresser {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptForPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openPrivacyPane() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    static func openScreenRecordingPane() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
    }

    /// 該狀態列視窗「真的顯示在畫面上」時回傳其座標。
    /// 選單列空間不足時，macOS 會把最左側的圖示藏起來：座標仍在畫面內但 kCGWindowIsOnscreen 為 false，
    /// 此時對座標點擊會誤觸前景 App 的選單，所以必須以 onscreen 為準。
    static func onscreenBounds(windowID: Int) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for w in list where (w[kCGWindowNumber as String] as? Int) == windowID {
            guard (w[kCGWindowIsOnscreen as String] as? Bool) == true,
                  let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: d), r.width > 0,
                  ScreenGeometry.xOnSomeScreen(r.midX) else { return nil }
            return r
        }
        return nil
    }

    /// 該視窗是否存在但目前被 macOS 藏起來（空間不足）
    static func isHiddenByOverflow(_ w: [String: Any]) -> Bool {
        (w[kCGWindowIsOnscreen as String] as? Bool) != true
    }

    /// 先移到目標讓對方拿到 hover 狀態，再按下、放開
    static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            down?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                up?.post(tap: .cghidEventTap)
            }
        }
    }
}

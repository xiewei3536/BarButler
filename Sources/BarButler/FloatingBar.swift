import AppKit
import SwiftUI
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
}

// MARK: - 隱藏圖示掃描（CGWindowList，免任何權限）

struct HiddenEntry: Identifiable {
    let id: Int          // windowNumber
    let pid: pid_t
    let name: String
    let icon: NSImage
    let x: CGFloat
}

enum HiddenItemScanner {
    /// 列出「‹ 左側」的第三方狀態列項目（= 被收合／永久隱藏的圖示），由左至右
    static func scan(leftOf boundaryX: CGFloat) -> [HiddenEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        let bands = ScreenGeometry.menuBarTopBandsCG()
        var out: [HiddenEntry] = []
        var seen = Set<String>()
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 25, // 狀態列項目層
                  let pidNum = w[kCGWindowOwnerPID as String] as? Int, pidNum != myPid,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let bDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bDict)
            else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            guard b.height >= 16, b.height <= 40, b.width >= 8, b.width <= 400 else { continue }
            guard bands.contains(where: { $0.contains(b.minY) }) else { continue }
            guard b.midX < boundaryX - 4 else { continue } // 只要 ‹ 左邊的
            let key = "\(pidNum)-\(Int(b.minX))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let pid = pid_t(pidNum)
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? (w[kCGWindowOwnerName as String] as? String) ?? "App"
            let icon = app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            out.append(HiddenEntry(id: num, pid: pid, name: name, icon: icon, x: b.minX))
        }
        return out.sorted { $0.x < $1.x }
    }
}

// MARK: - 點擊轉發（合成滑鼠事件，需要「輔助使用」）

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
                  let r = CGRect(dictionaryRepresentation: d), r.width > 0, xOnSomeScreen(r.midX) else { return nil }
            return r
        }
        return nil
    }

    /// 該視窗是否存在但目前被 macOS 藏起來（空間不足）
    static func isHiddenByOverflow(_ w: [String: Any]) -> Bool {
        (w[kCGWindowIsOnscreen as String] as? Bool) != true
    }

    static func click(at p: CGPoint) { syntheticClick(at: p) }

    private static func xOnSomeScreen(_ x: CGFloat) -> Bool {
        NSScreen.screens.contains { x >= $0.frame.minX && x <= $0.frame.maxX }
    }

    /// 先移到目標讓對方拿到 hover 狀態，再按下、放開
    private static func syntheticClick(at p: CGPoint) {
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

// MARK: - 懸浮面板

/// 可成為 key window 的無邊框非啟動面板：接收鍵盤（Esc／方向鍵）但不切換前景 App
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelState: ObservableObject {
    @Published var selected: Int?
}

final class FloatBar {
    weak var owner: StatusBarController?
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hoverTimer: Timer?
    private var outsideSince: Date?
    private var entries: [HiddenEntry] = []
    private let state = PanelState()

    var isOpen: Bool { panel != nil }

    func toggle() { isOpen ? close() : open() }

    func open(byHover: Bool = false) {
        close()
        guard let owner else { return }
        entries = HiddenItemScanner.scan(leftOf: owner.arrowScreenMinX ?? .greatestFiniteMagnitude)
        state.selected = nil

        let view = FloatBarView(
            entries: entries,
            showLabels: Prefs.shared.panelShowLabels,
            axTrusted: AXPresser.trusted,
            state: state,
            onTap: { [weak self] e in self?.handleTap(e) },
            onGrant: { [weak self] in
                self?.close()
                AXPresser.promptForPermission()
                AXPresser.openPrivacyPane()
            })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let p = KeyablePanel(contentRect: host.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = host

        // 靠著 ‹ 下方、貼齊右側
        let arrow = owner.arrowScreenFrame
        let screen = NSScreen.screens.first { s in arrow.map { s.frame.intersects($0) } ?? false } ?? NSScreen.main
        var origin = NSPoint.zero
        if let f = screen?.visibleFrame {
            var x = (arrow?.maxX ?? f.maxX) - size.width
            x = min(max(x, f.minX + 8), f.maxX - size.width - 8)
            origin = NSPoint(x: x, y: f.maxY - size.height - 6)
        }
        p.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 6))
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        panel = p
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(origin)
        }

        installMonitors()
        if byHover { startHoverWatch() }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        hoverTimer?.invalidate()
        hoverTimer = nil
        outsideSince = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: 監聽：點外面關閉、Esc／方向鍵、失去焦點

    private func installMonitors() {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(g) }

        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] ev in
            if ev.window != self?.panel { self?.close() }
            return ev
        }) { monitors.append(l) }

        if let k = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] ev in
            guard let s = self, s.isOpen else { return ev }
            if ev.modifierFlags.contains(.command) { s.close(); return nil } // 別讓 ⌘ 組合鍵誤傳到 App 主選單
            switch ev.keyCode {
            case 53: s.close(); return nil                                  // Esc
            case 123, 126: s.moveSelection(-1); return nil                  // ← ↑
            case 124, 125, 48: s.moveSelection(+1); return nil              // → ↓ Tab
            case 36, 49, 76:                                                // ↩ Space Enter
                if let i = s.state.selected, s.entries.indices.contains(i) { s.handleTap(s.entries[i]) }
                return nil
            default: return ev
            }
        }) { monitors.append(k) }

        if let p = panel {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
                    // 使用者切到別的視窗 → 稍後關閉（給滑鼠點擊面板的瞬間留餘地）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let s = self, let p = s.panel, !p.isKeyWindow else { return }
                        s.close()
                    }
                })
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let cur = state.selected ?? (delta > 0 ? -1 : entries.count)
        state.selected = (cur + delta + entries.count) % entries.count
    }

    /// 懸停開啟的面板：滑鼠離開「‹ ＋ 面板 ＋ 兩者之間的走廊」超過 0.6 秒就自動關閉
    private func startHoverWatch() {
        hoverTimer?.invalidate()
        outsideSince = nil
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let s = self, let p = s.panel else { return }
            let loc = NSEvent.mouseLocation
            var keep = p.frame.insetBy(dx: -16, dy: -16).contains(loc)
            if let a = s.owner?.arrowScreenFrame {
                keep = keep || a.insetBy(dx: -12, dy: -6).contains(loc)
                let left = min(a.minX, p.frame.minX) - 12
                let right = max(a.maxX, p.frame.maxX) + 12
                let corridor = NSRect(x: left, y: p.frame.maxY - 2, width: right - left,
                                      height: max(0, a.minY - p.frame.maxY) + 6)
                keep = keep || corridor.contains(loc)
            }
            if keep {
                s.outsideSince = nil
            } else if let t = s.outsideSince {
                if Date().timeIntervalSince(t) > 0.6 { s.close() }
            } else {
                s.outsideSince = Date()
            }
        }
    }

    // MARK: 點擊圖示 → 代點真正的狀態列圖示

    private func handleTap(_ e: HiddenEntry) {
        Log.panel.info("tap \(e.name, privacy: .public) win=\(e.id) trusted=\(AXPresser.trusted)")
        close()
        guard let owner else { return }
        guard AXPresser.trusted else {
            Toast.show(L.floatNeedAX.s, kind: .warning, near: owner.arrowScreenFrame)
            AXPresser.promptForPermission()
            return
        }
        owner.forwardClick(toWindow: e.id, name: e.name)
    }
}

// MARK: - 面板內容

struct FloatBarView: View {
    let entries: [HiddenEntry]
    let showLabels: Bool
    let axTrusted: Bool
    @ObservedObject var state: PanelState
    let onTap: (HiddenEntry) -> Void
    let onGrant: () -> Void

    private let perRow = 8

    private var rows: [[HiddenEntry]] {
        stride(from: 0, to: entries.count, by: perRow).map { Array(entries[$0..<min($0 + perRow, entries.count)]) }
    }

    var body: some View {
        VStack(spacing: 6) {
            if entries.isEmpty {
                emptyState
            } else {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(rows[r]) { e in cell(e) }
                    }
                }
            }
            footer
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func cell(_ e: HiddenEntry) -> some View {
        let idx = entries.firstIndex { $0.id == e.id }
        let selected = idx != nil && state.selected == idx
        return Button { onTap(e) } label: {
            VStack(spacing: 4) {
                Image(nsImage: e.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                if showLabels {
                    Text(e.name)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(width: 62)
                }
            }
            .padding(.vertical, 6)
            .frame(width: showLabels ? 70 : 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.12 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(FloatIconButtonStyle())
        .help(e.name)
        .onHover { hovering in if hovering { state.selected = idx } }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(L.floatEmpty.s)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var footer: some View {
        if !axTrusted {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(L.floatAXHint.s)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Button(L.floatGrant.s, action: onGrant)
                    .controlSize(.mini)
            }
            .padding(.top, 2)
        } else if !entries.isEmpty {
            Text(L.floatFooter.s)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
    }
}

struct FloatIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

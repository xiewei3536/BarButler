import AppKit
import SwiftUI
import ApplicationServices

// MARK: - 隱藏圖示掃描（CGWindowList，免任何權限）

struct HiddenEntry: Identifiable {
    let id: Int          // windowNumber
    let pid: pid_t
    let name: String
    let icon: NSImage
    let x: CGFloat
}

enum HiddenItemScanner {
    /// 列出「‹ 左側」的第三方狀態列項目（= 被收合／永久隱藏的圖示）
    static func scan(leftOf boundaryX: CGFloat) -> [HiddenEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPid = ProcessInfo.processInfo.processIdentifier
        var out: [HiddenEntry] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  layer == 25, // 狀態列項目層
                  let pidNum = w[kCGWindowOwnerPID as String] as? Int,
                  pidNum != Int(myPid),
                  let num = w[kCGWindowNumber as String] as? Int,
                  let bDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bDict)
            else { continue }
            guard b.height <= 40, b.width <= 400 else { continue }
            guard b.midX < boundaryX - 4 else { continue } // 只要箭頭左邊的

            let pid = pid_t(pidNum)
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName
                ?? (w[kCGWindowOwnerName as String] as? String)
                ?? "App"
            let icon = app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            out.append(HiddenEntry(id: num, pid: pid, name: name, icon: icon, x: b.minX))
        }
        return out.sorted { $0.x < $1.x }
    }
}

// MARK: - 點擊轉發（輔助使用 AXPress）

enum AXPresser {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func promptForPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 觸發該 App 的狀態列圖示：等圖示真正出現在畫面上，對其中心送出「合成滑鼠點擊」
    /// （與親手點擊等效，選單／彈窗一定會開）；圖示始終不在畫面上時退回 AXPress。
    static func trigger(entry: HiddenEntry, groupOfSamePid group: [HiddenEntry]) {
        guard let el = element(for: entry, group: group) else { return }
        attemptClick(el, attemptsLeft: 10)
    }

    private static func attemptClick(_ el: AXUIElement, attemptsLeft: Int) {
        if let f = frame(of: el), f.width > 0, xOnSomeScreen(f.midX) {
            syntheticClick(at: CGPoint(x: f.midX, y: f.midY))
            return
        }
        guard attemptsLeft > 0 else {
            AXUIElementPerformAction(el, kAXPressAction as CFString) // 最後手段
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            attemptClick(el, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func element(for entry: HiddenEntry, group: [HiddenEntry]) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(entry.pid)
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extrasAny = extrasRef, CFGetTypeID(extrasAny) == AXUIElementGetTypeID()
        else { return nil }
        let kids = children(of: extrasAny as! AXUIElement)
        guard !kids.isEmpty else { return nil }

        // 同一 App 有多個圖示時，用「由左至右的序位」對應
        let sortedKids = kids.sorted { (frame(of: $0)?.minX ?? 0) < (frame(of: $1)?.minX ?? 0) }
        let sortedGroup = group.sorted { $0.x < $1.x }
        let idx = sortedGroup.firstIndex { $0.id == entry.id } ?? 0
        return sortedKids[min(idx, sortedKids.count - 1)]
    }

    /// CFArray → [AXUIElement]（避免 Swift 泛型橋接靜默失敗）
    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let any = ref, CFGetTypeID(any) == CFArrayGetTypeID() else { return [] }
        let cf = any as! CFArray
        var out: [AXUIElement] = []
        for i in 0..<CFArrayGetCount(cf) {
            out.append(unsafeBitCast(CFArrayGetValueAtIndex(cf, i), to: AXUIElement.self))
        }
        return out
    }

    private static func frame(of el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, CFGetTypeID(p) == AXValueGetTypeID(),
              let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// AX 座標 x 軸與 NSScreen 全域座標一致，只需驗 x
    private static func xOnSomeScreen(_ x: CGFloat) -> Bool {
        NSScreen.screens.contains { x >= $0.frame.minX && x <= $0.frame.maxX }
    }

    private static func syntheticClick(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: p, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                         mouseCursorPosition: p, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            up?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - 懸浮面板

final class FloatBar {
    weak var owner: StatusBarController?
    private var panel: NSPanel?
    private var monitors: [Any] = []

    var isOpen: Bool { panel != nil }

    func toggle() { isOpen ? close() : open() }

    func open() {
        close()
        guard let owner else { return }
        let boundaryX = owner.arrowScreenMinX ?? .greatestFiniteMagnitude
        let entries = HiddenItemScanner.scan(leftOf: boundaryX)

        let view = FloatBarView(
            entries: entries,
            axTrusted: AXPresser.trusted,
            onTap: { [weak self] e in self?.handleTap(e, all: entries) },
            onGrant: { [weak self] in
                self?.close()
                AXPresser.promptForPermission()
            })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = host

        // 靠著箭頭下方、貼齊右側
        let arrow = owner.arrowScreenFrame
        let screen = NSScreen.screens.first { s in arrow.map { s.frame.intersects($0) } ?? false }
            ?? NSScreen.main
        if let f = screen?.visibleFrame {
            var x = (arrow?.maxX ?? f.maxX) - size.width
            x = min(max(x, f.minX + 8), f.maxX - size.width - 8)
            p.setFrameOrigin(NSPoint(x: x, y: f.maxY - size.height - 6))
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }

        // 點擊面板以外任何地方即關閉
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        } as Any)
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] ev in
            if ev.window != self?.panel { self?.close() }
            return ev
        }) {
            monitors.append(local)
        }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    private func handleTap(_ e: HiddenEntry, all: [HiddenEntry]) {
        close()
        guard let owner else { return }
        guard AXPresser.trusted else {
            // 未授權：退而求其次，展開真實選單列讓使用者直接點
            owner.setCollapsed(false, byHover: true)
            return
        }
        let group = all.filter { $0.pid == e.pid }
        if owner.collapsed {
            // 先展開讓圖示回到畫面上（用一般自動收合節奏，留時間操作對方選單）
            owner.setCollapsed(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                AXPresser.trigger(entry: e, groupOfSamePid: group)
            }
        } else {
            AXPresser.trigger(entry: e, groupOfSamePid: group)
        }
    }
}

// MARK: - 面板內容

struct FloatBarView: View {
    let entries: [HiddenEntry]
    let axTrusted: Bool
    let onTap: (HiddenEntry) -> Void
    let onGrant: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 6) {
                if entries.isEmpty {
                    Text(L.floatEmpty.s)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(entries) { e in
                        Button { onTap(e) } label: {
                            Image(nsImage: e.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 26, height: 26)
                                .padding(5)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(FloatIconButtonStyle())
                        .help(e.name)
                    }
                }
            }
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
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct FloatIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

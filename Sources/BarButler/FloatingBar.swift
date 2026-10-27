import AppKit
import SwiftUI

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
    private var entries: [BarItem] = []   // 鍵盤導覽順序（收合區在前、永久隱藏在後）
    private let state = PanelState()

    var isOpen: Bool { panel != nil }

    func toggle() { isOpen ? close() : open() }

    func open(byHover: Bool = false) {
        close()
        guard let owner else { return }
        let snap = owner.snapshot()
        let hidden = snap.items(in: .hidden)
        let always = snap.items(in: .alwaysHidden)
        entries = hidden + always
        state.selected = nil

        let view = FloatBarView(
            hidden: hidden,
            always: always,
            pendingRestore: owner.pendingRestoreCount,
            alwaysEnabled: Prefs.shared.alwaysHiddenEnabled,
            showLabels: Prefs.shared.panelShowLabels,
            axTrusted: AXPresser.trusted,
            state: state,
            indexOf: { [weak self] id in self?.entries.firstIndex { $0.windowID == id } },
            onTap: { [weak self] e in self?.handleTap(e) },
            onMove: { [weak self] e, dest in self?.handleMove(e, to: dest) },
            onArrange: { [weak self] in
                self?.close()
                NotificationCenter.default.post(name: .bbShowLayout, object: nil)
            },
            onRestore: { [weak self] in
                self?.close()
                self?.owner?.restoreNow()
            },
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
            var x = (arrow?.maxX ?? f.maxX) - size.width + 10
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
            // 面板內的右鍵選單是另一個視窗：點選單項目時不要關面板
            if ev.window != self?.panel, !(ev.window is NSPanel && ev.window?.level == .popUpMenu) { self?.close() }
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
                    // 使用者切到別的視窗 → 稍後關閉（給滑鼠點擊面板、開右鍵選單的瞬間留餘地）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let s = self, let p = s.panel, !p.isKeyWindow, NSApp.keyWindow == nil || NSApp.keyWindow != p,
                              !s.contextMenuOpen else { return }
                        s.close()
                    }
                })
        }
    }

    /// 右鍵選單開著（SwiftUI contextMenu 會讓面板暫時失去 key）
    private var contextMenuOpen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.className.contains("Menu") && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue }
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
            if s.contextMenuOpen { s.outsideSince = nil; return }
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

    // MARK: 點擊圖示 → 代點真正的狀態列圖示；右鍵 → 移到其他區塊

    private func handleTap(_ e: BarItem) {
        Log.panel.info("tap \(e.label, privacy: .public) win=\(e.windowID) trusted=\(AXPresser.trusted)")
        close()
        guard let owner else { return }
        guard AXPresser.trusted else {
            Toast.show(L.floatNeedAX.s, kind: .warning, near: owner.arrowScreenFrame)
            AXPresser.promptForPermission()
            return
        }
        owner.forwardClick(toWindow: e.windowID, name: e.label)
    }

    private func handleMove(_ e: BarItem, to dest: BarSection) {
        close()
        guard let owner else { return }
        guard AXPresser.trusted else {
            Toast.show(L.moveNeedsAX.s, kind: .warning, near: owner.arrowScreenFrame)
            AXPresser.promptForPermission()
            return
        }
        owner.moveItem(e, to: dest)
    }
}

// MARK: - 面板內容

struct FloatBarView: View {
    let hidden: [BarItem]
    let always: [BarItem]
    let pendingRestore: Int
    let alwaysEnabled: Bool
    let showLabels: Bool
    let axTrusted: Bool
    @ObservedObject var state: PanelState
    let indexOf: (Int) -> Int?
    let onTap: (BarItem) -> Void
    let onMove: (BarItem, BarSection) -> Void
    let onArrange: () -> Void
    let onRestore: () -> Void
    let onGrant: () -> Void

    private let maxPerRow = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if pendingRestore > 0, axTrusted { restoreBanner }
            if hidden.isEmpty && always.isEmpty {
                emptyState
            } else {
                grid(hidden)
                if !always.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash").font(.system(size: 9, weight: .semibold))
                        Text(L.sectionAlways.s).font(.system(size: 10, weight: .semibold))
                        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    grid(always).opacity(0.85)
                }
            }
            footer
        }
        .padding(10)
        .frame(minWidth: 230)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BB.accentColor)
            Text(L.panelTitle.s).font(.system(size: 11, weight: .semibold))
            Text("\(hidden.count + always.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer(minLength: 12)
            Button(action: onArrange) {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 9.5, weight: .semibold))
                    Text(L.panelArrange.s).font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L.menuArrange.s)
        }
        .padding(.horizontal, 2)
    }

    /// 有圖示被 macOS／其他 App 打亂、又因選單列太擠還沒自動歸位：讓使用者一鍵處理
    private var restoreBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(L.panelRestoreFmt.f(pendingRestore))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button(L.panelRestoreBtn.s, action: onRestore)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.1)))
    }

    private func grid(_ items: [BarItem]) -> some View {
        // 平均分排：8 個 → 4＋4，而不是 7＋1
        let rowCount = max(1, Int(ceil(Double(items.count) / Double(maxPerRow))))
        let perRow = max(1, Int(ceil(Double(items.count) / Double(rowCount))))
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(rows[r]) { e in cell(e) }
                }
            }
        }
    }

    private func cell(_ e: BarItem) -> some View {
        let idx = indexOf(e.windowID)
        let selected = idx != nil && state.selected == idx
        return Button { onTap(e) } label: {
            VStack(spacing: 4) {
                ItemIconView(item: e, size: 30)
                if showLabels {
                    Text(e.label)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(width: 62)
                }
            }
            .padding(.vertical, 6)
            .frame(width: showLabels ? 70 : 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.12 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(FloatIconButtonStyle())
        .help(e.label)
        .onHover { hovering in if hovering { state.selected = idx } }
        .contextMenu {
            Button { onMove(e, .shown) } label: { Label(L.moveToShown.s, systemImage: "pin.fill") }
            if alwaysEnabled {
                if e.section == .alwaysHidden {
                    Button { onMove(e, .hidden) } label: { Label(L.moveToHidden.s, systemImage: "tray.and.arrow.up") }
                } else {
                    Button { onMove(e, .alwaysHidden) } label: { Label(L.moveToAlways.s, systemImage: "eye.slash") }
                }
            }
            Divider()
            Button(action: onArrange) { Label(L.menuArrange.s, systemImage: "slider.horizontal.3") }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(L.floatEmpty.s)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300, alignment: .leading)
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
        } else if !(hidden.isEmpty && always.isEmpty) {
            Text(L.floatFooter.s)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
                .padding(.horizontal, 2)
        }
    }
}

/// 圖示：真實選單列圖示（有螢幕錄製權限時）＞ 系統項目的 SF Symbol ＞ App 圖示
struct ItemIconView: View {
    let item: BarItem
    var size: CGFloat = 28

    var body: some View {
        if let g = IconCache.shared.glyph(item.windowID) {
            Image(nsImage: g.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: size * 2.2, maxHeight: size * 0.62)
                .padding(.horizontal, 6)
                .frame(height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(g.isLight ? Color.black.opacity(0.72) : Color.white.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        } else if let sym = item.systemSymbol {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.28)], startPoint: .top, endPoint: .bottom))
                Image(systemName: sym)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        } else {
            Image(nsImage: item.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
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

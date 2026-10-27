import SwiftUI
import UniformTypeIdentifiers

// MARK: - 圖示配置頁（拖曳圖示到不同區塊 → ItemMover 代為 ⌘ 拖曳真正的圖示）

@MainActor
final class LayoutModel: ObservableObject {
    @Published var shown: [BarItem] = []
    @Published var hidden: [BarItem] = []
    @Published var always: [BarItem] = []
    @Published var busyText: String?
    @Published var notice: (text: String, ok: Bool)?
    @Published var axTrusted = AXPresser.trusted
    @Published var screenPermitted = IconCache.shared.permitted
    @Published var shownWidth: CGFloat = 0
    @Published var screenWidth: CGFloat = 1440
    @Published var iconsVersion = 0   // 圖示擷取更新時觸發重繪
    var dragging: BarItem?
    private var timer: Timer?
    private var noticeWork: DispatchWorkItem?

    private var controller: StatusBarController? { StatusBarController.current }

    func start() {
        refresh()
        warmUpIcons()
        timer?.invalidate()
        // 關閉視窗時 SwiftUI 不一定會呼叫 onDisappear：計時器自己確認視窗還看得到才更新（AX 查詢不便宜）
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard NSApp.windows.contains(where: { $0.identifier?.rawValue == "BBSettings" && $0.isVisible }) else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        axTrusted = AXPresser.trusted
        screenPermitted = IconCache.shared.permitted
        guard let c = controller, !ItemMover.shared.busy else { return }
        let snap = c.snapshot()
        if IconCache.shared.enabled {
            IconCache.shared.capture(snap.items)
            iconsVersion &+= 1
        }
        let s = snap.items(in: .shown), h = snap.items(in: .hidden), a = snap.items(in: .alwaysHidden)
        if s != shown { shown = s }
        if h != hidden { hidden = h }
        if a != always { always = a }
        shownWidth = snap.shownWidth
        screenWidth = snap.screenWidth
    }

    /// 開啟真實圖示時，收合中的圖示在畫面外擷取不到：短暫展開一次把它們都拍下來
    func warmUpIcons() {
        guard IconCache.shared.enabled, let c = controller, c.collapsed, !ItemMover.shared.busy else { return }
        c.beginEditing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            IconCache.shared.capture(c.snapshot(details: false).items)
            c.endEditing(after: 0.2)
            self?.iconsVersion &+= 1
            self?.refresh()
        }
    }

    func move(_ item: BarItem, to dest: BarSection) {
        guard item.section != dest else { return }
        guard let c = controller else { return }
        guard item.movable else { show(L.itemLocked.s, ok: false); return }
        guard AXPresser.trusted else {
            show(L.moveNeedsAX.s, ok: false)
            AXPresser.promptForPermission()
            return
        }
        busyText = L.movingFmt.f(item.label)
        Task { @MainActor in
            do {
                try await ItemMover.shared.move(windowID: item.windowID, to: dest, via: c)
                c.rememberMove(item.windowID, to: dest)
                show(L.movedFmt.f(item.label, dest.title), ok: true)
            } catch {
                show(ItemMover.message(for: error, label: item.label), ok: false)
            }
            busyText = nil
            refresh()
        }
    }

    func dropDragging(on dest: BarSection) {
        guard let d = dragging else { return }
        dragging = nil
        move(d, to: dest)
    }

    func relocate(rightEnd: Bool) {
        controller?.relocateToggle(rightEnd: rightEnd)
        busyText = "…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.busyText = nil
            self?.refresh()
        }
    }

    private func show(_ text: String, ok: Bool) {
        notice = (text, ok)
        noticeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 3 : 6), execute: w)
    }
}

struct LayoutTab: View {
    @EnvironmentObject var prefs: Prefs
    @StateObject private var model = LayoutModel()
    @State private var target: BarSection?

    var body: some View {
        VStack(spacing: 12) {
            if prefs.showWhatsNew { whatsNew }
            if !model.axTrusted { permissionCard }

            sectionCard(.shown, items: model.shown, icon: "pin.fill", color: .green, subtitle: L.sectionShownSub.s) {
                spaceMeter
            }
            sectionCard(.hidden, items: model.hidden, icon: "tray.full.fill", color: BB.accentColor, subtitle: L.sectionHiddenSub.s) {
                EmptyView()
            }
            if prefs.alwaysHiddenEnabled {
                sectionCard(.alwaysHidden, items: model.always, icon: "eye.slash.fill", color: .gray, subtitle: L.sectionAlwaysSub.s) {
                    EmptyView()
                }
            } else {
                alwaysOffCard
            }
            toolsCard
        }
        .overlay(alignment: .top) { statusBanner }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: prefs.alwaysHiddenEnabled) { _ in model.refresh() }
        .onChange(of: prefs.realIcons) { on in
            if on, !IconCache.shared.permitted {
                CGRequestScreenCaptureAccess()
                AXPresser.openScreenRecordingPane()
            }
            model.refresh()
            model.warmUpIcons()
        }
    }

    // MARK: 區塊

    private func sectionCard<Accessory: View>(_ s: BarSection, items: [BarItem], icon: String, color: Color,
                                              subtitle: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        let targeted = target == s
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient).frame(width: 22, height: 22)
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(s.title).font(.system(size: 13, weight: .semibold))
                        Text("\(items.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                accessory()
            }
            strip(s, items: items)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(targeted ? BB.accentColor : Color.primary.opacity(0.08), lineWidth: targeted ? 2 : 1)
                )
        )
        .onDrop(of: [UTType.plainText, UTType.text], isTargeted: Binding(
            get: { target == s },
            set: { on in
                if on { target = s } else if target == s { target = nil }
            })) { _ in
            model.dropDragging(on: s)
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }

    /// 像一小段選單列的圖示列
    private func strip(_ s: BarSection, items: [BarItem]) -> some View {
        Group {
            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.compact").font(.system(size: 11))
                    Text(L.sectionEmpty.s).font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            } else {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(items) { item in tile(item) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            }
        }
    }

    private func tile(_ item: BarItem) -> some View {
        LayoutTile(item: item, iconsVersion: model.iconsVersion)
            .opacity(model.busyText != nil ? 0.6 : 1)
            .onDrag {
                model.dragging = item
                return NSItemProvider(object: String(item.windowID) as NSString)
            }
            .contextMenu {
                if item.movable {
                    if item.section != .shown {
                        Button { model.move(item, to: .shown) } label: { Label(L.moveToShown.s, systemImage: "pin.fill") }
                    }
                    if item.section != .hidden {
                        Button { model.move(item, to: .hidden) } label: { Label(L.moveToHidden.s, systemImage: "tray.and.arrow.down") }
                    }
                    if prefs.alwaysHiddenEnabled, item.section != .alwaysHidden {
                        Button { model.move(item, to: .alwaysHidden) } label: { Label(L.moveToAlways.s, systemImage: "eye.slash") }
                    }
                } else {
                    Text(L.itemLocked.s)
                }
            }
    }

    // MARK: 附件

    private var spaceMeter: some View {
        let ratio = min(1, model.shownWidth / max(1, model.screenWidth))
        let warn = ratio > 0.45
        return VStack(alignment: .trailing, spacing: 3) {
            Text(L.spaceFmt.f(Int(model.shownWidth), Int(model.screenWidth)))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(warn ? .orange : .secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(warn ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.green.gradient))
                    .frame(width: 110 * ratio)
            }
            .frame(width: 110, height: 5)
        }
        .help(warn ? L.spaceWarn.s : "")
    }

    private var whatsNew: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(BB.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.whatsNewTitle.s).font(.system(size: 12.5, weight: .semibold))
                Text(L.whatsNewBody.s).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { prefs.showWhatsNew = false } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BB.accentColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BB.accentColor.opacity(0.2), lineWidth: 1))
        )
    }

    private var permissionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").font(.system(size: 14)).foregroundStyle(.orange)
            Text(L.needAXCard.s).font(.system(size: 12, weight: .medium))
            Spacer()
            Button(L.btnOpenPrivacy.s) {
                AXPresser.promptForPermission()
                AXPresser.openPrivacyPane()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
    }

    private var alwaysOffCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L.alwaysOffHint.s).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button(L.btnTurnOn.s) { prefs.alwaysHiddenEnabled = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var toolsCard: some View {
        Card {
            SettingRow(icon: "pin.circle.fill", color: .teal, title: L.rowRemember.s, subtitle: L.rowRememberSub.s) {
                Toggle("", isOn: $prefs.rememberLayout).labelsHidden().toggleStyle(.switch).tint(BB.accentColor)
                    .onChange(of: prefs.rememberLayout) { on in
                        if on { StatusBarController.current?.rememberLayout("enabled") } else { LayoutMemory.shared.forget() }
                    }
            }
            Divider().padding(.leading, 56).opacity(0.6)
            SettingRow(icon: "photo.on.rectangle", color: .pink, title: L.layoutRealIcons.s, subtitle: L.layoutRealIconsSub.s) {
                HStack(spacing: 8) {
                    if prefs.realIcons && !model.screenPermitted {
                        Button(L.layoutGrantScreen.s) {
                            CGRequestScreenCaptureAccess()
                            AXPresser.openScreenRecordingPane()
                        }
                        .controlSize(.small)
                    }
                    Toggle("", isOn: $prefs.realIcons).labelsHidden().toggleStyle(.switch).tint(BB.accentColor)
                }
            }
            Divider().padding(.leading, 56).opacity(0.6)
            HStack(spacing: 8) {
                Button { model.refresh(); model.warmUpIcons() } label: {
                    Label(L.layoutRefresh.s, systemImage: "arrow.clockwise")
                }
                Spacer()
                Button { model.relocate(rightEnd: true) } label: {
                    Label(L.layoutHideAll.s, systemImage: "rectangle.righthalf.inset.filled.arrow.right")
                }
                .help(L.layoutHideAllHelp.s)
                Button { model.relocate(rightEnd: false) } label: {
                    Label(L.layoutShowAll.s, systemImage: "rectangle.lefthalf.inset.filled.arrow.left")
                }
                .help(L.layoutShowAllHelp.s)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if let busy = model.busyText {
            banner(text: busy, icon: nil, color: BB.accentColor)
        } else if let n = model.notice {
            banner(text: n.text, icon: n.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                   color: n.ok ? .green : .orange)
        }
    }

    private func banner(text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(color)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.top, -2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 單一圖示方塊：圖示＋名稱；系統固定項目加鎖頭
private struct LayoutTile: View {
    let item: BarItem
    let iconsVersion: Int
    @State private var hover = false

    var body: some View {
        VStack(spacing: 3) {
            ItemIconView(item: item, size: 26)
                .overlay(alignment: .bottomTrailing) {
                    if !item.movable {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2.5)
                            .background(Circle().fill(Color.gray))
                            .offset(x: 3, y: 3)
                    }
                }
                .frame(height: 28)
            Text(item.label)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary.opacity(item.movable ? 0.85 : 0.5))
                .frame(width: 66)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.08 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hover = $0 }
        .help(item.movable ? "\(item.label) — \(L.dragHint.s)" : "\(item.label) — \(L.itemLocked.s)")
        .id("\(item.windowID)-\(iconsVersion)")
    }
}

/// 自動換行的水平排列（macOS 13 Layout）
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

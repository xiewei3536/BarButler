import SwiftUI
import ServiceManagement

// MARK: - 共用視覺元件

enum BB {
    static let accent = LinearGradient(
        colors: [Color(red: 0.44, green: 0.36, blue: 0.97), Color(red: 0.60, green: 0.36, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentColor = Color(red: 0.48, green: 0.36, blue: 0.97)
}

/// 毛玻璃視窗背景
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct SettingRow<Control: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

private struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 56).opacity(0.6) }
}

private func switchToggle(_ binding: Binding<Bool>) -> some View {
    Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).tint(BB.accentColor)
}

// MARK: - 主設定視窗

struct SettingsRoot: View {
    @EnvironmentObject var prefs: Prefs

    enum Tab: CaseIterable { case general, advanced, about }
    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                Group {
                    switch tab {
                    case .general: GeneralTab()
                    case .advanced: AdvancedTab()
                    case .about: AboutTab()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .padding(.top, 4)
            }
        }
        .frame(width: 600, height: 610)
        .background(VisualEffectBackground().ignoresSafeArea())
        .id(prefs.language) // 語言切換時整體重繪
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(BB.accent)
                        .frame(width: 38, height: 38)
                        .shadow(color: BB.accentColor.opacity(0.4), radius: 6, y: 2)
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("BarButler").font(.system(size: 16, weight: .bold))
                    Text(L.appName.s).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                tabBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 34) // 讓出紅綠燈空間
            .padding(.bottom, 12)
            LinearGradient(colors: [BB.accentColor.opacity(0), BB.accentColor.opacity(0.35), BB.accentColor.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.horizontal, 18)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            tabButton(.general, icon: "gearshape.fill", label: L.tabGeneral.s)
            tabButton(.advanced, icon: "wand.and.stars", label: L.tabAdvanced.s)
            tabButton(.about, icon: "info.circle.fill", label: L.tabAbout.s)
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func tabButton(_ t: Tab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { tab = t }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(tab == t ? AnyShapeStyle(BB.accent) : AnyShapeStyle(Color.clear)))
            .foregroundStyle(tab == t ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 一般

struct GeneralTab: View {
    @EnvironmentObject var prefs: Prefs
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 14) {
            previewCard

            Card {
                SettingRow(icon: "globe", color: .blue, title: L.rowLanguage.s) {
                    Picker("", selection: $prefs.language) {
                        Text(L.langAuto.s).tag("auto")
                        Text("English").tag("en")
                        Text("繁體中文").tag("zh-Hant")
                        Text("简体中文").tag("zh-Hans")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                RowDivider()
                SettingRow(icon: "power", color: .green, title: L.rowLaunch.s, subtitle: L.rowLaunchSub.s) {
                    switchToggle(launchBinding)
                }
            }

            Card {
                SettingRow(icon: "rectangle.topthird.inset.filled", color: .purple,
                           title: L.rowExpandStyle.s, subtitle: L.rowExpandStyleSub.s) {
                    Picker("", selection: $prefs.clickMode) {
                        Text(L.modeMenubar.s).tag("menubar")
                        Text(L.modeFloat.s).tag("float")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
                RowDivider()
                SettingRow(icon: "chevron.left.forwardslash.chevron.right", color: .indigo, title: L.rowIconStyle.s) {
                    Picker("", selection: $prefs.iconStyle) {
                        Image(systemName: "chevron.left").tag("chevron")
                        Image(systemName: "ellipsis.circle").tag("dots")
                        Image(systemName: "arrow.left.to.line.compact").tag("arrows")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }
                RowDivider()
                SettingRow(icon: "timer", color: .orange,
                           title: L.rowAutoCollapse.s, subtitle: L.rowAutoCollapseSub.s) {
                    Picker("", selection: $prefs.autoCollapseSeconds) {
                        Text(L.never.s).tag(0)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { s in
                            Text(L.secondsFmt.f(s)).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                RowDivider()
                SettingRow(icon: "cursorarrow.motionlines", color: .pink,
                           title: L.rowHover.s, subtitle: L.rowHoverSub.s) {
                    switchToggle($prefs.hoverToExpand)
                }
                RowDivider()
                SettingRow(icon: "hand.tap.fill", color: .teal,
                           title: L.rowClickAway.s, subtitle: L.rowClickAwaySub.s) {
                    switchToggle($prefs.clickAwayCollapse)
                }
            }

            tipBox

            if let e = loginError {
                Text("\(L.alertLoginFail.s): \(e)")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye").font(.system(size: 11, weight: .semibold)).foregroundStyle(BB.accentColor)
                Text(L.previewTitle.s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(prefs.isFloatMode ? L.previewFloat.s : L.previewMenubar.s)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            MockMenuBar(mode: prefs.clickMode, iconStyle: prefs.iconStyle)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BB.accentColor.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(BB.accentColor.opacity(0.15), lineWidth: 1))
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                prefs.objectWillChange.send()
            })
    }

    private var tipBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(.yellow)
            Text(L.tipDrag.s)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L.btnTutorial.s) {
                NotificationCenter.default.post(name: .bbShowOnboarding, object: nil)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.yellow.opacity(0.09)))
    }
}

// MARK: - 進階

struct AdvancedTab: View {
    @EnvironmentObject var prefs: Prefs
    @State private var axTrusted = AXPresser.trusted
    @State private var copied: String?
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private let commands: [(String, Tr)] = [
        ("barbutler://toggle", L.cmdToggle),
        ("barbutler://show", L.cmdShow),
        ("barbutler://hide", L.cmdHide),
        ("barbutler://peek", L.cmdPeek),
        ("barbutler://panel", L.cmdPanel),
        ("barbutler://mode/float", L.modeFloat),
        ("barbutler://mode/menubar", L.modeMenubar),
        ("barbutler://settings", L.cmdSettings),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Card {
                SettingRow(icon: "keyboard", color: .indigo, title: L.rowHotkey.s, subtitle: L.rowHotkeySub.s) {
                    HStack(spacing: 8) {
                        HotkeyRecorder()
                        switchToggle($prefs.hotkeyEnabled)
                    }
                }
            }

            Card {
                SettingRow(icon: "hand.raised.fill", color: axTrusted ? .green : .orange,
                           title: L.rowPermission.s, subtitle: L.rowPermissionSub.s) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle().fill(axTrusted ? Color.green : Color.orange).frame(width: 7, height: 7)
                            Text(axTrusted ? L.permGranted.s : L.permMissing.s)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if !axTrusted {
                            Button(L.btnOpenPrivacy.s) {
                                AXPresser.promptForPermission()
                                AXPresser.openPrivacyPane()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .onReceive(ticker) { _ in axTrusted = AXPresser.trusted }

            Card {
                SettingRow(icon: "ruler", color: .cyan, title: L.rowBoundary.s, subtitle: L.rowBoundarySub.s) {
                    switchToggle($prefs.showBoundaryWhileArranging)
                }
                RowDivider()
                SettingRow(icon: "textformat", color: .mint, title: L.rowPanelLabels.s, subtitle: L.rowPanelLabelsSub.s) {
                    switchToggle($prefs.panelShowLabels)
                }
                RowDivider()
                SettingRow(icon: "rectangle.expand.vertical", color: .orange, title: L.rowBorrow.s, subtitle: L.rowBorrowSub.s) {
                    switchToggle($prefs.borrowOnExpand)
                }
                RowDivider()
                SettingRow(icon: "eye.slash.fill", color: .purple, title: L.rowAlways.s, subtitle: L.rowAlwaysSub.s) {
                    switchToggle($prefs.alwaysHiddenEnabled)
                }
                RowDivider()
                SettingRow(icon: "sparkle.magnifyingglass", color: .teal, title: L.rowPeek.s, subtitle: L.rowPeekSub.s) {
                    Button(L.btnPeekNow.s) {
                        NotificationCenter.default.post(name: .bbPeek, object: nil)
                    }
                }
            }

            Card {
                SettingRow(icon: "terminal.fill", color: .gray, title: L.rowAutomation.s, subtitle: L.rowAutomationSub.s) {
                    EmptyView()
                }
                VStack(spacing: 0) {
                    ForEach(commands, id: \.0) { cmd, desc in
                        HStack(spacing: 10) {
                            Text(cmd)
                                .font(.system(size: 11.5, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Text(copied == cmd ? L.copied.s : desc.s)
                                .font(.system(size: 11))
                                .foregroundStyle(copied == cmd ? BB.accentColor : .secondary)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                                copied = cmd
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if copied == cmd { copied = nil } }
                            } label: {
                                Image(systemName: copied == cmd ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 8)
            }

            Card {
                SettingRow(icon: "arrow.counterclockwise", color: .gray, title: L.rowReset.s, subtitle: L.rowResetSub.s) {
                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .bbResetPositions, object: nil)
                    } label: {
                        Text(L.btnReset.s)
                    }
                }
            }
        }
    }
}

// MARK: - 快捷鍵錄製

struct HotkeyRecorder: View {
    @EnvironmentObject var prefs: Prefs
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L.recordPrompt.s
                 : HotkeyManager.display(keyCode: prefs.hotkeyKeyCode, modifiersRaw: prefs.hotkeyModifiers))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 76)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recording ? BB.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(recording ? BB.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(L.clickToSet.s)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotkeyManager.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            if ev.keyCode == 53 { stop(); return nil } // Esc 取消
            let flags = ev.modifierFlags.intersection([.command, .option, .control, .shift])
            let needsModifier = !(HotkeyManager.keyNames[Int(ev.keyCode)]?.hasPrefix("F") ?? false)
            if needsModifier && flags.intersection([.command, .option, .control]).isEmpty {
                return nil // 要求至少一個修飾鍵，避免吃掉一般輸入
            }
            prefs.hotkeyKeyCode = Int(ev.keyCode)
            prefs.hotkeyModifiers = flags.rawValue
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        HotkeyManager.shared.resume()
    }
}

// MARK: - 關於

struct AboutTab: View {
    @EnvironmentObject var prefs: Prefs
    @State private var autoCheck = UpdaterManager.shared.updater?.automaticallyChecksForUpdates ?? true
    @State private var autoDownload = UpdaterManager.shared.updater?.automaticallyDownloadsUpdates ?? true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 6)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            VStack(spacing: 4) {
                Text("BarButler").font(.system(size: 22, weight: .bold))
                Text(L.appName.s).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(L.versionFmt.f(version)).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Text(L.aboutTagline.s)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BB.accentColor)
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text(L.aboutUniversal.s)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Link(destination: URL(string: "https://github.com/xiewei3536/BarButler")!) {
                    Label(L.aboutGitHub.s, systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/xiewei3536/BarButler/issues")!) {
                    Label(L.aboutIssue.s, systemImage: "ladybug")
                }
            }
            .font(.system(size: 12))

            if UpdaterManager.shared.available {
                Card {
                    SettingRow(icon: "arrow.triangle.2.circlepath", color: .blue, title: L.rowUpdates.s) {
                        Button(L.btnCheckNow.s) { UpdaterManager.shared.checkForUpdates() }
                            .controlSize(.small)
                    }
                    RowDivider()
                    SettingRow(icon: "clock.arrow.circlepath", color: .cyan, title: L.rowAutoCheck.s) {
                        switchToggle($autoCheck)
                            .onChange(of: autoCheck) { v in UpdaterManager.shared.updater?.automaticallyChecksForUpdates = v }
                    }
                    RowDivider()
                    SettingRow(icon: "square.and.arrow.down", color: .green, title: L.rowAutoDownload.s) {
                        switchToggle($autoDownload)
                            .onChange(of: autoDownload) { v in UpdaterManager.shared.updater?.automaticallyDownloadsUpdates = v }
                    }
                }
            }
            Spacer()
            HStack {
                Text("© 2026 Bowei · MIT").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button(L.menuQuit.s) { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }
}

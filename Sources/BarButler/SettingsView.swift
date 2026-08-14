import SwiftUI
import ServiceManagement

// MARK: - 共用視覺元件

enum BB {
    static let accent = LinearGradient(
        colors: [Color(red: 0.44, green: 0.36, blue: 0.97), Color(red: 0.60, green: 0.36, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentColor = Color(red: 0.48, green: 0.36, blue: 0.97)
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
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

// MARK: - 主設定視窗

struct SettingsRoot: View {
    @EnvironmentObject var prefs: Prefs

    enum Tab: CaseIterable { case general, advanced, about }
    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                Group {
                    switch tab {
                    case .general: GeneralTab()
                    case .advanced: AdvancedTab()
                    case .about: AboutTab()
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 520)
        .id(prefs.language) // 語言切換時整體重繪
    }

    private var header: some View {
        VStack(spacing: 12) {
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
        }
        .padding(.top, 34) // 讓出紅綠燈空間
        .padding(.bottom, 12)
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
            .background(
                Capsule().fill(tab == t ? AnyShapeStyle(BB.accent) : AnyShapeStyle(Color.clear))
            )
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
                Divider().padding(.leading, 56)
                SettingRow(icon: "power", color: .green,
                           title: L.rowLaunch.s, subtitle: L.rowLaunchSub.s) {
                    Toggle("", isOn: launchBinding).labelsHidden().toggleStyle(.switch)
                        .tint(BB.accentColor)
                }
            }

            Card {
                SettingRow(icon: "rectangle.topthird.inset.filled", color: .purple,
                           title: L.rowExpandStyle.s, subtitle: L.rowExpandStyleSub.s) {
                    Picker("", selection: $prefs.clickMode) {
                        Text(L.modeMenubar.s).tag("menubar")
                        Text(L.modeFloat.s).tag("float")
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                Divider().padding(.leading, 56)
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
                Divider().padding(.leading, 56)
                SettingRow(icon: "cursorarrow.motionlines", color: .pink,
                           title: L.rowHover.s, subtitle: L.rowHoverSub.s) {
                    Toggle("", isOn: $prefs.hoverToExpand).labelsHidden().toggleStyle(.switch)
                        .tint(BB.accentColor)
                }
            }

            tipBox

            if let e = loginError {
                Text("\(L.alertLoginFail.s): \(e)")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
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
            Spacer()
            Button(L.btnTutorial.s) {
                NotificationCenter.default.post(name: .bbShowOnboarding, object: nil)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.yellow.opacity(0.08))
        )
    }
}

// MARK: - 進階

struct AdvancedTab: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 14) {
            Card {
                SettingRow(icon: "keyboard", color: .indigo,
                           title: L.rowHotkey.s, subtitle: L.rowHotkeySub.s) {
                    HStack(spacing: 8) {
                        HotkeyRecorder()
                        Toggle("", isOn: $prefs.hotkeyEnabled).labelsHidden().toggleStyle(.switch)
                            .tint(BB.accentColor)
                    }
                }
            }

            Card {
                SettingRow(icon: "eye.slash.fill", color: .purple,
                           title: L.rowAlways.s, subtitle: L.rowAlwaysSub.s) {
                    Toggle("", isOn: $prefs.alwaysHiddenEnabled).labelsHidden().toggleStyle(.switch)
                        .tint(BB.accentColor)
                }
            }

            Card {
                SettingRow(icon: "sparkle.magnifyingglass", color: .teal,
                           title: L.rowPeek.s, subtitle: L.rowPeekSub.s) {
                    Button(L.btnPeekNow.s) {
                        NotificationCenter.default.post(name: .bbPeek, object: nil)
                    }
                    .controlSize(.regular)
                }
            }

            Card {
                SettingRow(icon: "arrow.counterclockwise", color: .gray,
                           title: L.rowReset.s, subtitle: L.rowResetSub.s) {
                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .bbResetPositions, object: nil)
                    } label: {
                        Text(L.btnReset.s)
                    }
                    .controlSize(.regular)
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
                                .strokeBorder(recording ? BB.accentColor : Color.primary.opacity(0.12),
                                              lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(L.clickToSet.s)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
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
    }
}

// MARK: - 關於

struct AboutTab: View {
    @EnvironmentObject var prefs: Prefs
    @State private var autoCheck = UpdaterManager.shared.updater?.automaticallyChecksForUpdates ?? true
    @State private var autoDownload = UpdaterManager.shared.updater?.automaticallyDownloadsUpdates ?? true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            VStack(spacing: 4) {
                Text("BarButler").font(.system(size: 22, weight: .bold))
                Text(L.appName.s).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(L.versionFmt.f(version))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
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

            if UpdaterManager.shared.available {
                Card {
                    SettingRow(icon: "arrow.triangle.2.circlepath", color: .blue,
                               title: L.rowUpdates.s) {
                        Button(L.btnCheckNow.s) { UpdaterManager.shared.checkForUpdates() }
                            .controlSize(.small)
                    }
                    Divider().padding(.leading, 56)
                    SettingRow(icon: "clock.arrow.circlepath", color: .cyan,
                               title: L.rowAutoCheck.s) {
                        Toggle("", isOn: $autoCheck).labelsHidden().toggleStyle(.switch)
                            .tint(BB.accentColor)
                            .onChange(of: autoCheck) { v in
                                UpdaterManager.shared.updater?.automaticallyChecksForUpdates = v
                            }
                    }
                    Divider().padding(.leading, 56)
                    SettingRow(icon: "square.and.arrow.down", color: .green,
                               title: L.rowAutoDownload.s) {
                        Toggle("", isOn: $autoDownload).labelsHidden().toggleStyle(.switch)
                            .tint(BB.accentColor)
                            .onChange(of: autoDownload) { v in
                                UpdaterManager.shared.updater?.automaticallyDownloadsUpdates = v
                            }
                    }
                }
            }
            Spacer()
            HStack {
                Text("© 2026 Bowei").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button(L.menuQuit.s) { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

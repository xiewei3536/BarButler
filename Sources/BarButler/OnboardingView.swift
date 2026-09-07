import SwiftUI
import AppKit
import ServiceManagement

/// 新手教學：含動態模擬選單列（會依目前設定的模式演示）
struct OnboardingView: View {
    @EnvironmentObject var prefs: Prefs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            header
            MockMenuBar(mode: prefs.clickMode, iconStyle: prefs.iconStyle)
                .padding(.horizontal, 32)
                .padding(.top, 20)
            steps
                .padding(.horizontal, 36)
                .padding(.top, 8)
            Spacer(minLength: 10)
            footer
        }
        .frame(width: 620, height: 600)
        .background(VisualEffectBackground().ignoresSafeArea())
        .id(prefs.language)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BB.accent)
                    .frame(width: 68, height: 68)
                    .shadow(color: BB.accentColor.opacity(0.45), radius: 12, y: 4)
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(L.obTitle.s).font(.system(size: 22, weight: .bold))
            Text(L.obSubtitle.s).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.top, 38)
    }

    private var steps: some View {
        VStack(spacing: 12) {
            StepRow(icon: "command", title: L.obStep1T.s, desc: L.obStep1D.s)
            StepRow(icon: "cursorarrow.click.2", title: L.obStep2T.s, desc: L.obStep2D.s)
            StepRow(icon: "sparkles", title: L.obStep3T.s, desc: L.obStep3D.s)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $launchAtLogin) {
                Text(L.obLaunch.s).font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
            Button(L.obSettings.s) {
                NotificationCenter.default.post(name: .bbShowSettings, object: nil)
            }
            .controlSize(.regular)
            Spacer()
            Button {
                (NSApp.delegate as? AppDelegate)?.closeOnboarding()
            } label: {
                Text(L.obStart.s)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(BB.accent))
                    .shadow(color: BB.accentColor.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
}

private struct StepRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(BB.accent).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

/// 會自己展開／收合的模擬選單列；懸浮面板模式時改演示下方彈出面板
struct MockMenuBar: View {
    var mode: String = "menubar"
    var iconStyle: String = "chevron"
    @State private var open = false
    private let hideable = ["message.fill", "cloud.fill", "music.note", "camera.fill"]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            bar
            if mode == "float", open {
                panelMock
                    .padding(.top, 38)
                    .padding(.trailing, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(height: 88, alignment: .top)
        .task(id: mode) {
            open = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                if Task.isCancelled { break }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { open.toggle() }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 13) {
            Image(systemName: "apple.logo").font(.system(size: 12))
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer()
            if mode == "menubar", open {
                ForEach(hideable, id: \.self) { ic in
                    Image(systemName: ic)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            Image(systemName: IconStyleKit.symbolName(style: iconStyle, collapsed: !open))
                .font(.system(size: 11, weight: .bold))
            Image(systemName: "wifi")
            Image(systemName: "battery.100")
            Text("14:32").font(.system(size: 11, weight: .medium))
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        )
    }

    private var panelMock: some View {
        HStack(spacing: 12) {
            ForEach(hideable, id: \.self) { ic in
                Image(systemName: ic).font(.system(size: 13))
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(white: 0.2))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        )
    }
}

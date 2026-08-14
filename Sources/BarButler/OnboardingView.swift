import SwiftUI
import AppKit

/// 新手教學：含動態模擬選單列
struct OnboardingView: View {
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 0) {
            header
            MockMenuBar()
                .padding(.horizontal, 32)
                .padding(.top, 22)
            steps
                .padding(.horizontal, 36)
                .padding(.top, 22)
            Spacer(minLength: 12)
            footer
        }
        .frame(width: 620, height: 560)
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
        .padding(.top, 40)
    }

    private var steps: some View {
        VStack(spacing: 14) {
            StepRow(n: 1, icon: "command", title: L.obStep1T.s, desc: L.obStep1D.s)
            StepRow(n: 2, icon: "cursorarrow.click.2", title: L.obStep2T.s, desc: L.obStep2D.s)
            StepRow(n: 3, icon: "sparkles", title: L.obStep3T.s, desc: L.obStep3D.s)
        }
    }

    private var footer: some View {
        HStack {
            Button(L.obSettings.s) {
                NotificationCenter.default.post(name: .bbShowSettings, object: nil)
            }
            .controlSize(.large)
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
        .padding(.bottom, 26)
    }
}

private struct StepRow: View {
    let n: Int
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

/// 會自己收合／展開的模擬選單列
struct MockMenuBar: View {
    @State private var collapsed = false
    private let hideable = ["message.fill", "cloud.fill", "music.note", "camera.fill"]

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "apple.logo").font(.system(size: 12))
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer()
            if !collapsed {
                ForEach(hideable, id: \.self) { ic in
                    Image(systemName: ic)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            Image(systemName: collapsed ? "chevron.right" : "chevron.left")
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    collapsed.toggle()
                }
            }
        }
    }
}

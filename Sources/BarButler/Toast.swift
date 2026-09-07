import AppKit
import SwiftUI

enum ToastKind { case success, info, warning }

/// 輕量提示：出現在 ‹ 下方（或螢幕右上角），2.8 秒後自動淡出
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String, kind: ToastKind = .success, near anchor: NSRect? = nil) {
        panel?.orderOut(nil)

        let (symbol, color): (String, Color) = {
            switch kind {
            case .success: return ("checkmark.circle.fill", .green)
            case .info: return ("info.circle.fill", BB.accentColor)
            case .warning: return ("exclamationmark.triangle.fill", .orange)
            }
        }()

        let content = HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))

        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = host

        // 定位：優先貼在 ‹ 下方，否則螢幕右上角
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.contains(NSPoint(x: a.midX, y: a.midY)) } }
            ?? NSScreen.main
        if let f = screen?.visibleFrame {
            var x = anchor.map { $0.midX - size.width / 2 } ?? (f.maxX - size.width - 16)
            x = min(max(x, f.minX + 12), f.maxX - size.width - 12)
            let y = f.maxY - size.height - 8
            p.setFrameOrigin(NSPoint(x: x, y: y + 8))
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 1
                p.animator().setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak p] in
            guard let p, p == panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if panel == p { panel = nil }
            })
        }
    }
}

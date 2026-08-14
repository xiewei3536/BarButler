// 產生 App 圖示：紫色漸層圓角方形 + 「● ● ● ▏‹」收合意象
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// 底板（留邊距，符合 macOS 圖示規範）
let inset: CGFloat = 70
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let plate = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)

// 陰影
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.set()
NSColor(calibratedRed: 0.25, green: 0.19, blue: 0.72, alpha: 1).setFill()
plate.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// 主漸層
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.52, green: 0.38, blue: 0.99, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.90, alpha: 1),
    NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.74, alpha: 1),
])!
grad.draw(in: plate, angle: -70)

// 左上柔光
let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.22),
                      ending: NSColor.white.withAlphaComponent(0))!
glow.draw(in: plate, relativeCenterPosition: NSPoint(x: -0.35, y: 0.55))

// 頂部模擬「選單列」細條
let barRect = NSRect(x: rect.minX + 70, y: rect.maxY - 150, width: rect.width - 140, height: 64)
let barPath = NSBezierPath(roundedRect: barRect, xRadius: 32, yRadius: 32)
NSColor.white.withAlphaComponent(0.16).setFill()
barPath.fill()

// 白色圖形：三顆漸淡圓點 + 分隔線 + 左角括號
NSGraphicsContext.current?.saveGraphicsState()
let gShadow = NSShadow()
gShadow.shadowBlurRadius = 18
gShadow.shadowOffset = NSSize(width: 0, height: -8)
gShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
gShadow.set()

let cy = size / 2 - 40
func dot(_ cx: CGFloat, _ alpha: CGFloat) {
    let r: CGFloat = 52
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
}
dot(268, 0.35)
dot(408, 0.60)
dot(548, 1.00)

// 分隔線
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 648, y: cy - 165, width: 26, height: 330),
             xRadius: 13, yRadius: 13).fill()

// 左角括號 ‹
let chevron = NSBezierPath()
chevron.move(to: NSPoint(x: 836, y: cy + 108))
chevron.line(to: NSPoint(x: 742, y: cy))
chevron.line(to: NSPoint(x: 836, y: cy - 108))
chevron.lineWidth = 54
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
NSColor.white.setStroke()
chevron.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("無法產生 PNG\n", stderr)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("圖示已輸出：\(outPath)")

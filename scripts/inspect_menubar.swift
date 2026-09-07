// 診斷工具：列出所有狀態列項目視窗（layer 25）與開啟中的選單（layer 101）
// 用法：swift scripts/inspect_menubar.swift
import AppKit
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
var rows: [(String, Int, CGRect, Int)] = []
var menus = 0
for w in list {
    guard let layer = w[kCGWindowLayer as String] as? Int,
          let b = w[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: b) else { continue }
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? 0
    let num = (w[kCGWindowNumber as String] as? Int) ?? 0
    if layer == 25 && r.height <= 40 { rows.append((owner, pid, r, num)) }
    if layer == menuLevel, (w[kCGWindowIsOnscreen as String] as? Bool) == true { menus += 1 }
}
rows.sort { $0.2.minX < $1.2.minX }
print("screen maxX:", NSScreen.main!.frame.maxX, " open menus:", menus)
for (o, p, r, n) in rows {
    let vis = r.midX >= 0 ? "on " : "OFF"
    print(String(format: "%@ x=%7.0f w=%5.0f  #%-6d pid=%-6d %@", vis, r.minX, r.width, n, p, o))
}

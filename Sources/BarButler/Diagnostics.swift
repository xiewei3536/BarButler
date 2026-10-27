import AppKit

/// 診斷報告：選單列配置、權限、系統狀態與近期事件，存成文字檔（~/Library/Logs/BarButler/）
enum Diagnostics {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BarButler", isDirectory: true)
    }

    static func report() -> String {
        let p = Prefs.shared
        var out: [String] = []
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        out.append("BarButler \(v) — diagnostics \(ISO8601DateFormatter().string(from: Date()))")
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(hardwareModel)")
        out.append("screens: " + NSScreen.screens.map { s in
            "\(Int(s.frame.width))x\(Int(s.frame.height))@\(Int(s.backingScaleFactor))x" + (s == NSScreen.screens.first ? " (main)" : "")
        }.joined(separator: ", "))
        out.append("prefs: mode=\(p.clickMode) collapsed=\(p.collapsed) autoCollapse=\(p.autoCollapseSeconds)s hover=\(p.hoverToExpand) "
                   + "clickAway=\(p.clickAwayCollapse) alwaysHidden=\(p.alwaysHiddenEnabled) realIcons=\(p.realIcons) borrow=\(p.borrowOnExpand)")
        out.append("permissions: accessibility=\(AXPresser.trusted) screenRecording=\(IconCache.shared.permitted)")
        out.append("system: \(SystemMonitor.shared.summary)")
        out.append("positions: " + ["BB_Toggle", "BB_Pusher", "BB_AlwaysSep"].map { n in
            "\(n)=\(UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(n)").map { "\($0)" } ?? "nil")"
        }.joined(separator: " "))
        if let c = StatusBarController.current {
            out.append("bar: \(c.healthSummary)")
            let snap = c.snapshot()
            if let a = snap.anchors {
                var line = "anchors: ‹ #\(a.toggleID) x=\(Int(a.toggle.minX)) w=\(Int(a.toggle.width)) visible=\(a.toggleOnScreen)"
                if let pf = a.pusher { line += " · divider #\(a.pusherID ?? -1) x=\(Int(pf.minX)) w=\(Int(pf.width))" }
                if let sf = a.sep { line += " · always-hidden divider #\(a.sepID ?? -1) x=\(Int(sf.minX)) w=\(Int(sf.width))" }
                out.append(line)
            }
            out.append("items (left → right): \(snap.items.count)")
            for it in snap.items {
                let sec = "[\(it.section)]".padding(toLength: 15, withPad: " ", startingAt: 0)
                out.append("  \(sec) \(it.label)  #\(it.windowID)  x=\(Int(it.frame.minX)) w=\(Int(it.frame.width))  "
                           + (it.onScreen ? "visible" : "not visible") + (it.movable ? "" : "  (fixed)")
                           + "  \(it.bundleID ?? "-")")
            }
        }
        out.append("")
        out.append("recent events:")
        out.append(Journal.shared.text)
        return out.joined(separator: "\n")
    }

    /// 寫入報告檔；name 為 nil 時加上時間戳
    @discardableResult
    static func write(name: String? = nil) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let safe = name.map { n -> String in
                let base = String(URL(fileURLWithPath: n).lastPathComponent
                    .filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }.prefix(60))
                return base.hasSuffix(".txt") && base.count > 4 ? base : "diagnostics.txt"
            }
            let url = directory.appendingPathComponent(safe ?? "diagnostics-\(f.string(from: Date())).txt")
            try report().write(to: url, atomically: true, encoding: .utf8)
            Log.event("diagnostics written: \(url.lastPathComponent)")
            return url
        } catch {
            Log.event("diagnostics failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}

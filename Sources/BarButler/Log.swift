import Foundation
import os

/// 統一日誌：`/usr/bin/log show --predicate 'subsystem == "com.bowei.barbutler"' --last 5m --info`
/// info 等級只留在記憶體；會影響配置的事件用 `Log.event`（notice 等級，會寫入磁碟並進診斷報告）
enum Log {
    static let core = Logger(subsystem: "com.bowei.barbutler", category: "core")
    static let panel = Logger(subsystem: "com.bowei.barbutler", category: "panel")
    static let hotkey = Logger(subsystem: "com.bowei.barbutler", category: "hotkey")
    static let layout = Logger(subsystem: "com.bowei.barbutler", category: "layout")

    /// 重要事件：寫入系統日誌（持久）＋近期事件紀錄（診斷報告用）
    static func event(_ s: String) {
        core.notice("\(s, privacy: .public)")
        Journal.shared.add(s)
    }
}

/// 近期事件環形紀錄（只在記憶體，最多 500 行）
final class Journal {
    static let shared = Journal()
    private var lines: [String] = []
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    func add(_ s: String) {
        lines.append("\(fmt.string(from: Date()))  \(s)")
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }

    var text: String { lines.joined(separator: "\n") }
}

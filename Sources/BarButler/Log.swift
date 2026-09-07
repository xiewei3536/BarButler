import Foundation
import os

/// 統一日誌：`/usr/bin/log show --predicate 'subsystem == "com.bowei.barbutler"' --last 5m --info`
enum Log {
    static let core = Logger(subsystem: "com.bowei.barbutler", category: "core")
    static let panel = Logger(subsystem: "com.bowei.barbutler", category: "panel")
    static let hotkey = Logger(subsystem: "com.bowei.barbutler", category: "hotkey")
}

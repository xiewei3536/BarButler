import AppKit

/// 圖示配置記憶：記下使用者決定的每個圖示在哪個區塊（透過 BarButler 移動、或自己按住 ⌘ 拖曳之後），
/// 之後若被 macOS 或其他 App 打亂（重新開機、App 更新重開、選單列重排…），自動移回原區塊。
///
/// 只記「使用者確認過」的配置：移動成功只記被移動的那一個；全部收起／顯示、開啟記憶時整份重記；
/// 使用者 ⌘ 拖曳後只記換了區塊的圖示。從沒見過的新圖示不動（macOS 會把它放在最左邊＝收合區）。
final class LayoutMemory {
    static let shared = LayoutMemory()
    private let key = "bb.layoutPins"
    private(set) var pins: [String: Int]
    private var failures: [String: Int] = [:]

    private init() {
        pins = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    /// 跨重新啟動仍穩定的識別：bundle id ＋ 系統識別名（像 com.apple.menuextra.battery）或同 App 內的順序。
    /// 不給識別（＝不記、不歸位）的情況：
    /// - 沒有 bundle id（開發中的執行檔等臨時圖示）
    /// - 這次讀不到該 App 的輔助使用資訊（剛喚醒時常逾時）：識別會從系統識別名退化成順序，可能對錯圖示
    /// - 同一個識別出現兩次（同一 App 開了兩個、或識別名重複）：分不清就不碰
    /// 有些 App 把狀態文字塞進 AXIdentifier（例如 OneDrive），所以只採用「反向網域名稱」格式的識別名。
    static func identities(_ items: [BarItem]) -> [Int: String] {
        var out: [Int: String] = [:]
        var ordinal: [String: Int] = [:]
        var seen: [String: Int] = [:]
        for it in items.sorted(by: { $0.frame.minX > $1.frame.minX }) {   // 由右至左編號（右側較少變動）
            guard let app = it.bundleID, !it.axUnavailable else { continue }
            let k: String
            if let sub = it.axIdentifier, isStableIdentifier(sub) {
                k = "\(app)|\(sub)"
            } else {
                let n = ordinal[app, default: 0]
                ordinal[app] = n + 1
                k = "\(app)|#\(n)"
            }
            seen[k, default: 0] += 1
            out[it.windowID] = k
        }
        return out.filter { seen[$0.value] == 1 }
    }

    private static func isStableIdentifier(_ s: String) -> Bool {
        s.count <= 80 && s.contains(".") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }

    /// 整份重記（以目前畫面為準）；目前沒在執行、或這次讀不到資訊的 App 保留原本的記憶
    func record(_ snap: BarSnapshot, reason: String) {
        guard snap.anchors != nil, !snap.items.isEmpty else { return }
        let ids = Self.identities(snap.items)
        let recordedApps = Set(snap.items.filter { ids[$0.windowID] != nil }.compactMap(\.bundleID))
        var next = pins.filter { k, _ in
            let app = String(k.split(separator: "|").first ?? "")
            return app.contains(".") && !recordedApps.contains(app)   // 舊格式／臨時圖示的紀錄順便清掉
        }
        for it in snap.items { if let k = ids[it.windowID] { next[k] = it.section.rawValue } }
        guard next != pins else { return }
        pins = next
        failures.removeAll()
        save()
        Log.event("layout remembered (\(reason)): \(snap.items(in: .shown).count) shown, "
                  + "\(snap.items(in: .hidden).count) hidden, \(snap.items(in: .alwaysHidden).count) always-hidden")
    }

    /// 只記一個圖示（使用者剛移動它）
    func pin(_ windowID: Int, to section: BarSection, in snap: BarSnapshot) {
        guard let k = Self.identities(snap.items)[windowID] else { return }
        failures[k] = nil
        guard pins[k] != section.rawValue else { return }
        pins[k] = section.rawValue
        save()
        Log.event("layout remembered: \(k) → \(section)")
    }

    /// 與記憶不符、且可以移動的圖示（最多 limit 個）
    func mismatches(_ snap: BarSnapshot, alwaysEnabled: Bool, limit: Int = 6) -> [(BarItem, BarSection)] {
        guard !pins.isEmpty else { return [] }
        let ids = Self.identities(snap.items)
        var out: [(BarItem, BarSection)] = []
        for it in snap.items where it.movable {
            guard let k = ids[it.windowID], let raw = pins[k], var want = BarSection(rawValue: raw) else { continue }
            if want == .alwaysHidden && !alwaysEnabled { want = .hidden }
            guard want != it.section, failures[k, default: 0] < 3 else { continue }
            out.append((it, want))
            if out.count >= limit { break }
        }
        return out
    }

    func noteFailure(_ item: BarItem, in snap: BarSnapshot) {
        guard let k = Self.identities(snap.items)[item.windowID] else { return }
        failures[k, default: 0] += 1
    }

    func forget() {
        pins = [:]
        failures.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
        Log.event("layout memory cleared")
    }

    private func save() { UserDefaults.standard.set(pins, forKey: key) }
}

import Foundation

/// Shared balanced rows for rendering and keyboard navigation. Eight items form
/// 4 + 4, and up/down keeps the same column instead of behaving like left/right.
enum PanelNavigation {
    enum Movement { case horizontal(Int), vertical(Int) }

    static func rowSizes(count: Int, maxPerRow: Int = 7) -> [Int] {
        guard count > 0 else { return [] }
        let rows = Int(ceil(Double(count) / Double(max(1, maxPerRow))))
        let perRow = Int(ceil(Double(count) / Double(rows)))
        return stride(from: 0, to: count, by: perRow).map { min(perRow, count - $0) }
    }

    static func next(selected: Int?, movement: Movement, rows: [Int]) -> Int? {
        let rows = rows.filter { $0 > 0 }
        let total = rows.reduce(0, +)
        guard total > 0 else { return nil }
        let delta: Int
        switch movement { case .horizontal(let d), .vertical(let d): delta = d }
        guard let selected, (0..<total).contains(selected) else { return delta < 0 ? total - 1 : 0 }
        switch movement {
        case .horizontal:
            return ((selected + delta) % total + total) % total
        case .vertical:
            var start = 0
            for (row, count) in rows.enumerated() {
                if selected < start + count {
                    let nextRow = ((row + delta) % rows.count + rows.count) % rows.count
                    return rows.prefix(nextRow).reduce(0, +) + min(selected - start, rows[nextRow] - 1)
                }
                start += count
            }
            return nil
        }
    }
}

extension BarItem {
    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        let text = [label, appName, bundleID ?? ""].joined(separator: " ")
        return terms.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

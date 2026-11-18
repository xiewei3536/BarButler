import Foundation

/// Launch time, with a deterministic PID tie-break, prevents simultaneous
/// instances from both terminating. The caller excludes terminated processes.
struct AppInstanceIdentity {
    let pid: Int32
    let launchedAt: Date?

    func precedes(_ other: Self) -> Bool {
        guard pid != other.pid else { return false }
        let lhs = launchedAt ?? .distantPast, rhs = other.launchedAt ?? .distantPast
        return lhs == rhs ? pid < other.pid : lhs < rhs
    }
}

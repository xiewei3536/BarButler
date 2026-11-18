import Foundation

/// A single, bounded repair transaction. AppKit may ignore saved status-item
/// positions after a display transition; verify geometry after every attempt and
/// escalate to rebuilding only our own anchors instead of repeating forever.
/// All entry points and scheduled callbacks run on the main thread.
final class StatusItemRecovery {
    enum Stage: CaseIterable { case preferredPosition, geometry, recreateAnchors }
    enum Outcome: Equatable { case recovered, failed, cancelled }
    typealias Completion = (Outcome) -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private let schedule: Scheduler
    private var generation: UInt64 = 0
    private var active: UInt64?
    private var completions: [Completion] = []
    var isRunning: Bool { active != nil }

    init(schedule: @escaping Scheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }) {
        self.schedule = schedule
    }

    /// Concurrent callers share the existing transaction, not another set of
    /// remove/recreate callbacks. Each completion is delivered exactly once.
    func join(_ completion: @escaping Completion) {
        precondition(isRunning)
        completions.append(completion)
    }

    func recover(canContinue: @escaping () -> Bool, isHealthy: @escaping () -> Bool,
                 perform: @escaping (Stage) -> Void, completion: @escaping Completion) {
        if isRunning { join(completion); return }
        generation &+= 1
        let token = generation
        active = token
        completions = [completion]
        advance(token, index: 0, canContinue: canContinue, isHealthy: isHealthy, perform: perform)
    }

    func cancel() {
        guard let token = active else { return }
        finish(token, with: .cancelled)
    }

    private func advance(_ token: UInt64, index: Int, canContinue: @escaping () -> Bool,
                         isHealthy: @escaping () -> Bool, perform: @escaping (Stage) -> Void) {
        guard active == token else { return } // A stale callback must not touch a new repair.
        guard canContinue() else { finish(token, with: .cancelled); return }
        if isHealthy() { finish(token, with: .recovered); return }
        let stages = Stage.allCases
        guard index < stages.count else { finish(token, with: .failed); return }
        let stage = stages[index]
        perform(stage)
        guard active == token else { return }
        let delay: TimeInterval = stage == .recreateAnchors ? 1 : 0.35
        schedule(delay) { [weak self] in
            self?.advance(token, index: index + 1, canContinue: canContinue,
                          isHealthy: isHealthy, perform: perform)
        }
    }

    private func finish(_ token: UInt64, with outcome: Outcome) {
        guard active == token else { return }
        active = nil
        let callbacks = completions
        completions.removeAll()
        // Clear state first: a completion is allowed to start a fresh transaction.
        callbacks.forEach { $0(outcome) }
    }
}

/// Exhaustion persists until a genuine system-settled event or manual retry.
/// A sliding time window otherwise replays the same failed repair every ten minutes.
struct StatusItemRepairBudget {
    private(set) var attempts = 0
    mutating func take() -> Bool {
        guard attempts < 2 else { return false }
        attempts += 1
        return true
    }
    mutating func reset() { attempts = 0 }
}

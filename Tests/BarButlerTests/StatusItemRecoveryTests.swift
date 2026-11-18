#if !BARBUTLER_STANDALONE_TESTS
import XCTest
@testable import BarButler
#endif
import Foundation

final class StatusItemRecoveryTests: XCTestCase {
    private final class Clock {
        var work: [() -> Void] = []
        func schedule(_ delay: TimeInterval, _ callback: @escaping () -> Void) { work.append(callback) }
        func next() { if !work.isEmpty { work.removeFirst()() } }
        func drain() { while !work.isEmpty { next() } }
    }

    func testHealthyAnchorsDoNotGetRecreated() {
        let recovery = StatusItemRecovery(schedule: { _, _ in })
        var stages: [StatusItemRecovery.Stage] = [], outcomes: [StatusItemRecovery.Outcome] = []
        recovery.recover(canContinue: { true }, isHealthy: { true },
                         perform: { stages.append($0) }, completion: { outcomes.append($0) })
        XCTAssertTrue(stages.isEmpty)
        XCTAssertEqual(outcomes, [.recovered])
        XCTAssertFalse(recovery.isRunning)
    }

    func testIgnoredPositionWritesEscalateToRecreatingOnlyOwnAnchors() {
        let clock = Clock()
        let subject = StatusItemRecovery(schedule: clock.schedule)
        var healthy = false
        var stages: [StatusItemRecovery.Stage] = [], outcomes: [StatusItemRecovery.Outcome] = []
        subject.recover(canContinue: { true }, isHealthy: { healthy }, perform: {
            stages.append($0)
            if $0 == .recreateAnchors { healthy = true }
        }, completion: { outcomes.append($0) })
        clock.drain()
        XCTAssertEqual(stages, [.preferredPosition, .geometry, .recreateAnchors])
        XCTAssertEqual(outcomes, [.recovered])
        XCTAssertFalse(subject.isRunning)
    }

    func testSuccessfulFirstStageDoesNotRecreateToggle() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var healthy = false, stages: [StatusItemRecovery.Stage] = []
        var outcome: StatusItemRecovery.Outcome?
        recovery.recover(canContinue: { true }, isHealthy: { healthy }, perform: {
            stages.append($0); healthy = true
        }, completion: { outcome = $0 })
        XCTAssertNil(outcome) // Geometry must settle before success is reported.
        clock.drain()
        XCTAssertEqual(stages, [.preferredPosition])
        XCTAssertEqual(outcome, .recovered)
    }

    func testAllFailedStagesReturnFailureRatherThanFalseSuccessOrLooping() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var stages: [StatusItemRecovery.Stage] = [], outcomes: [StatusItemRecovery.Outcome] = []
        recovery.recover(canContinue: { true }, isHealthy: { false },
                         perform: { stages.append($0) }, completion: { outcomes.append($0) })
        clock.drain()
        XCTAssertEqual(stages.count, 3)
        XCTAssertEqual(outcomes, [.failed])
        XCTAssertFalse(recovery.isRunning)
        XCTAssertTrue(clock.work.isEmpty)
    }

    func testConcurrentRequestsJoinInsteadOfOverlappingRebuilds() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var stages = 0, outcomes: [StatusItemRecovery.Outcome] = []
        for _ in 0..<3 {
            recovery.recover(canContinue: { true }, isHealthy: { false },
                             perform: { _ in stages += 1 }, completion: { outcomes.append($0) })
        }
        XCTAssertEqual(stages, 1)
        clock.drain()
        XCTAssertEqual(stages, 3)
        XCTAssertEqual(outcomes, [.failed, .failed, .failed])
    }

    func testSleepCancelsAllWaitersExactlyOnceAndStopsQueuedRebuilds() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var stages = 0, outcomes: [StatusItemRecovery.Outcome] = []
        recovery.recover(canContinue: { true }, isHealthy: { false },
                         perform: { _ in stages += 1 }, completion: { outcomes.append($0) })
        recovery.join { outcomes.append($0) }
        recovery.cancel()
        recovery.cancel()
        clock.drain()
        XCTAssertEqual(stages, 1)
        XCTAssertEqual(outcomes, [.cancelled, .cancelled])
        XCTAssertFalse(recovery.isRunning)
    }

    func testDisplayTransitionInvalidatesDelayedGeometryChanges() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var systemGeneration = 1
        let startGeneration = systemGeneration
        var stages = 0, outcome: StatusItemRecovery.Outcome?
        recovery.recover(canContinue: { systemGeneration == startGeneration }, isHealthy: { false },
                         perform: { _ in stages += 1 }, completion: { outcome = $0 })
        systemGeneration += 1
        clock.drain()
        XCTAssertEqual(stages, 1)
        XCTAssertEqual(outcome, .cancelled)
    }

    func testCallbackFromBeforeSleepCannotFinishOrMutateNewRepair() {
        let clock = Clock()
        let recovery = StatusItemRecovery(schedule: clock.schedule)
        var oldStages = 0, newStages = 0
        var oldOutcome: StatusItemRecovery.Outcome?, newOutcome: StatusItemRecovery.Outcome?
        recovery.recover(canContinue: { true }, isHealthy: { false },
                         perform: { _ in oldStages += 1 }, completion: { oldOutcome = $0 })
        recovery.cancel()
        recovery.recover(canContinue: { true }, isHealthy: { false },
                         perform: { _ in newStages += 1 }, completion: { newOutcome = $0 })
        clock.next() // The first transaction's queued callback.
        XCTAssertTrue(recovery.isRunning)
        XCTAssertNil(newOutcome)
        XCTAssertEqual(oldStages, 1)
        XCTAssertEqual(newStages, 1)
        clock.drain()
        XCTAssertEqual(oldOutcome, .cancelled)
        XCTAssertEqual(newOutcome, .failed)
        XCTAssertEqual(newStages, 3)
    }

    func testUnsafeSystemDoesNotStartAnyRebuild() {
        let recovery = StatusItemRecovery(schedule: { _, _ in })
        var stages = 0, outcome: StatusItemRecovery.Outcome?
        recovery.recover(canContinue: { false }, isHealthy: { false },
                         perform: { _ in stages += 1 }, completion: { outcome = $0 })
        XCTAssertEqual(stages, 0)
        XCTAssertEqual(outcome, .cancelled)
    }

    func testRepairBudgetCannotRestartItselfOnEveryWatchdogTick() {
        var budget = StatusItemRepairBudget()
        XCTAssertTrue(budget.take())
        XCTAssertTrue(budget.take())
        for _ in 0..<1000 { XCTAssertFalse(budget.take()) }
        XCTAssertEqual(budget.attempts, 2)
        budget.reset()
        XCTAssertTrue(budget.take())
        XCTAssertEqual(budget.attempts, 1)
    }
}

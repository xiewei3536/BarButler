#if !BARBUTLER_STANDALONE_TESTS
import XCTest
@testable import BarButler
#endif
import Foundation

final class AppInstanceIdentityTests: XCTestCase {
    func testOverlappingLaunchesKeepOnlyTheOlderProcess() {
        let older = AppInstanceIdentity(pid: 200, launchedAt: Date(timeIntervalSince1970: 1))
        let newer = AppInstanceIdentity(pid: 100, launchedAt: Date(timeIntervalSince1970: 2))
        XCTAssertTrue(older.precedes(newer))
        XCTAssertFalse(newer.precedes(older))
        XCTAssertFalse(older.precedes(older))
    }

    func testEqualOrMissingLaunchTimesUseOneDeterministicWinner() {
        for date in [nil, Date(timeIntervalSince1970: 1)] {
            let a = AppInstanceIdentity(pid: 100, launchedAt: date)
            let b = AppInstanceIdentity(pid: 200, launchedAt: date)
            XCTAssertTrue(a.precedes(b))
            XCTAssertFalse(b.precedes(a))
        }
    }

    func testReusedPidIsNotMistakenForAnotherInstance() {
        let a = AppInstanceIdentity(pid: 100, launchedAt: Date(timeIntervalSince1970: 1))
        let b = AppInstanceIdentity(pid: 100, launchedAt: Date(timeIntervalSince1970: 2))
        XCTAssertFalse(a.precedes(b))
        XCTAssertFalse(b.precedes(a))
    }
}

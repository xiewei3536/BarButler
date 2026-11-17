#if !BARBUTLER_STANDALONE_TESTS
import XCTest
@testable import BarButler
#endif
import AppKit

final class SingleItemPresentationTests: XCTestCase {
    private func item(_ id: Int, _ x: CGFloat, section: BarSection = .hidden,
                      pid: pid_t = 42, identifier: String? = nil) -> BarItem {
        BarItem(windowID: id, pid: pid, bundleID: "com.example.fixture", appName: "Fixture",
                label: "Fixture \(id)", axIdentifier: identifier, windowTitle: nil,
                frame: CGRect(x: x, y: 0, width: 24, height: 24), onScreen: x >= 0,
                section: section, movable: true)
    }

    private func snapshot(_ items: [BarItem], sep: Int? = 92) -> BarSnapshot {
        BarSnapshot(anchors: BarAnchors(toggleID: 90, toggle: CGRect(x: 500, y: 0, width: 24, height: 24),
                    toggleOnScreen: true, pusherID: 91, pusher: CGRect(x: -4500, y: 0, width: 5000, height: 24),
                    sepID: sep, sep: sep.map { _ in CGRect(x: -9600, y: 0, width: 5000, height: 24) }), items: items)
    }

    func testReturnTicketPreservesBothNeighboursAndRoundTrips() throws {
        let items = [item(1, -90), item(2, -60), item(3, -30)]
        let ticket = TemporaryItemLocation(item: items[1], snapshot: snapshot(items), launchedAt: 123)
        XCTAssertEqual(ticket.leftNeighbour, 1)
        XCTAssertEqual(ticket.rightNeighbour, 3)
        XCTAssertEqual(ticket.destination(in: snapshot(items), alwaysEnabled: true), .init(windowID: 3, side: .before))
        XCTAssertEqual(try JSONDecoder().decode(TemporaryItemLocation.self, from: JSONEncoder().encode(ticket)), ticket)
    }

    func testFallbackUsesLeftNeighbourWhenRightNeighbourQuits() {
        let items = [item(1, -90), item(2, -60), item(3, -30)]
        let ticket = TemporaryItemLocation(item: items[1], snapshot: snapshot(items), launchedAt: nil)
        XCTAssertEqual(ticket.destination(in: snapshot([items[0]]), alwaysEnabled: true), .init(windowID: 1, side: .after))
    }

    func testMissingNeighboursFallBackToHiddenBoundary() {
        let target = item(2, -60)
        let ticket = TemporaryItemLocation(item: target, snapshot: snapshot([target]), launchedAt: nil)
        XCTAssertEqual(ticket.destination(in: snapshot([]), alwaysEnabled: true), .init(windowID: 91, side: .before))
    }

    func testAlwaysHiddenReturnsToItsOwnBoundary() {
        let target = item(2, -9000, section: .alwaysHidden)
        let ticket = TemporaryItemLocation(item: target, snapshot: snapshot([target]), launchedAt: nil)
        XCTAssertEqual(ticket.destination(in: snapshot([]), alwaysEnabled: true), .init(windowID: 92, side: .before))
        XCTAssertEqual(ticket.destination(in: snapshot([], sep: nil), alwaysEnabled: false), .init(windowID: 91, side: .before))
        XCTAssertNil(ticket.destination(in: snapshot([], sep: nil), alwaysEnabled: true))
    }

    func testNeighbourMovedToAnotherSectionIsNotUsed() {
        let items = [item(1, -90), item(2, -60), item(3, -30)]
        let ticket = TemporaryItemLocation(item: items[1], snapshot: snapshot(items), launchedAt: nil)
        let changed = [items[0].inSection(.shown), items[2].inSection(.alwaysHidden)]
        XCTAssertEqual(ticket.destination(in: snapshot(changed), alwaysEnabled: true), .init(windowID: 91, side: .before))
    }

    func testStaleProcessOrReusedWindowCannotMatchTicket() {
        let target = item(2, -60)
        let ticket = TemporaryItemLocation(item: target, snapshot: snapshot([target]), launchedAt: 100)
        XCTAssertTrue(ticket.matches(target, launchedAt: 100))
        XCTAssertFalse(ticket.matches(item(2, -60, pid: 43), launchedAt: 100))
        XCTAssertFalse(ticket.matches(item(3, -60), launchedAt: 100))
        XCTAssertFalse(ticket.matches(target, launchedAt: 200))
        XCTAssertFalse(ticket.matches(target, launchedAt: nil))
    }

    func testShownItemCannotBecomeReturnTicket() {
        let target = item(2, 600, section: .shown)
        let ticket = TemporaryItemLocation(item: target, snapshot: snapshot([target]), launchedAt: nil)
        XCTAssertFalse(ticket.matches(target, launchedAt: nil))
        XCTAssertNil(ticket.destination(in: snapshot([]), alwaysEnabled: true))
    }

    func testMenuIsNeverRehiddenWhileOpenRegardlessOfElapsedTime() {
        var policy = RevealDismissalPolicy()
        for time in [0.0, 0.5, 5, 60, 3600] {
            XCTAssertFalse(policy.shouldRestore(elapsed: time, interfaceOpen: true))
        }
        XCTAssertFalse(policy.shouldRestore(elapsed: 3601, interfaceOpen: false))
        XCTAssertTrue(policy.shouldRestore(elapsed: 3601.2, interfaceOpen: false))
    }

    func testMenuAnimationAndSubmenuGapDoNotTriggerPrematureRestore() {
        var policy = RevealDismissalPolicy()
        XCTAssertFalse(policy.shouldRestore(elapsed: 0.1, interfaceOpen: true))
        XCTAssertFalse(policy.shouldRestore(elapsed: 0.2, interfaceOpen: false))
        XCTAssertFalse(policy.shouldRestore(elapsed: 1.0, interfaceOpen: false))
        XCTAssertFalse(policy.shouldRestore(elapsed: 1.1, interfaceOpen: true))
        XCTAssertFalse(policy.shouldRestore(elapsed: 2.0, interfaceOpen: false))
        XCTAssertTrue(policy.shouldRestore(elapsed: 2.2, interfaceOpen: false))
    }

    func testActionOnlyIconGetsGracePeriodThenRestores() {
        var policy = RevealDismissalPolicy()
        XCTAssertFalse(policy.shouldRestore(elapsed: 0.5, interfaceOpen: false))
        XCTAssertFalse(policy.shouldRestore(elapsed: 1.79, interfaceOpen: false))
        XCTAssertFalse(policy.shouldRestore(elapsed: 1.8, interfaceOpen: false))
        XCTAssertTrue(policy.shouldRestore(elapsed: 2, interfaceOpen: false))
    }

    func testDirectedEventsHaveWindowIdentityAndCommandOnlyOnDown() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let down = try XCTUnwrap(DirectedMenuBarEvent.make(.leftMouseDown, point: CGPoint(x: 20_000, y: 20_000),
                                    windowID: 123, pid: 42, source: source, command: true))
        let up = try XCTUnwrap(DirectedMenuBarEvent.make(.leftMouseUp, point: .zero,
                                    windowID: 456, pid: 42, source: source))
        XCTAssertEqual(down.getIntegerValueField(.mouseEventWindowUnderMousePointer), 123)
        XCTAssertEqual(down.getIntegerValueField(try XCTUnwrap(CGEventField(rawValue: 0x33))), 123)
        XCTAssertEqual(up.getIntegerValueField(.eventTargetUnixProcessID), 42)
        XCTAssertTrue(down.flags.contains(.maskCommand))
        XCTAssertFalse(up.flags.contains(.maskCommand))
    }

    func testLogicalSectionCopyPreservesMetadata() {
        var target = item(1, 500, section: .shown, identifier: "com.example.item")
        target.axUnavailable = true
        let logical = target.inSection(.hidden)
        XCTAssertEqual(logical.section, .hidden)
        XCTAssertEqual(logical.windowID, target.windowID)
        XCTAssertEqual(logical.axIdentifier, target.axIdentifier)
        XCTAssertTrue(logical.axUnavailable)
    }

    func testBalancedGridAndKeyboardRowsAgree() {
        XCTAssertEqual(PanelNavigation.rowSizes(count: 8), [4, 4])
        XCTAssertEqual(PanelNavigation.rowSizes(count: 15), [5, 5, 5])
        XCTAssertEqual(PanelNavigation.rowSizes(count: 0), [])
        XCTAssertEqual(PanelNavigation.rowSizes(count: 3, maxPerRow: 0), [1, 1, 1])
    }

    func testKeyboardNavigationPreservesColumnAndWraps() {
        let rows = [4, 4, 2]
        XCTAssertEqual(PanelNavigation.next(selected: 1, movement: .vertical(1), rows: rows), 5)
        XCTAssertEqual(PanelNavigation.next(selected: 7, movement: .vertical(1), rows: rows), 9)
        XCTAssertEqual(PanelNavigation.next(selected: 0, movement: .vertical(-1), rows: rows), 8)
        XCTAssertEqual(PanelNavigation.next(selected: 0, movement: .horizontal(-1), rows: rows), 9)
        XCTAssertEqual(PanelNavigation.next(selected: nil, movement: .horizontal(-1), rows: rows), 9)
        XCTAssertNil(PanelNavigation.next(selected: 0, movement: .vertical(1), rows: []))
    }

    func testSearchIsCaseInsensitiveAndSupportsMultipleTerms() {
        let target = item(1, -30)
        XCTAssertTrue(target.matchesSearch("  FIXTURE  1  "))
        XCTAssertTrue(target.matchesSearch("com.example"))
        XCTAssertTrue(target.matchesSearch("   "))
        XCTAssertFalse(target.matchesSearch("another app"))
    }

    func testAmbiguousLayoutIdentifiersAreNotRemembered() {
        let duplicateA = item(1, -100, identifier: "com.example.duplicate")
        let duplicateB = item(2, -70, identifier: "com.example.duplicate")
        XCTAssertTrue(LayoutMemory.identities([duplicateA, duplicateB]).isEmpty)
        var unavailable = item(3, -40)
        unavailable.axUnavailable = true
        XCTAssertTrue(LayoutMemory.identities([unavailable]).isEmpty)
    }

    func testCorruptHotkeyValuesCannotReachUnsignedConversion() {
        XCTAssertTrue(HotkeyManager.validKeyCode(11))
        XCTAssertFalse(HotkeyManager.validKeyCode(-1))
        XCTAssertFalse(HotkeyManager.validKeyCode(Int.max))
    }

    func testDropPointsLandInsideTheCorrectHalfOfAnchor() {
        let frame = CGRect(x: -5000, y: 0, width: 5016, height: 24)
        XCTAssertEqual(ItemMoveDestination(windowID: 1, side: .before).point(in: frame), CGPoint(x: -4999, y: 12))
        XCTAssertEqual(ItemMoveDestination(windowID: 1, side: .after).point(in: frame), CGPoint(x: 15, y: 12))
    }
}

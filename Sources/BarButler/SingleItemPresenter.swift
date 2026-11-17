import AppKit

/// A return ticket is written before moving anything. Window + PID + process
/// launch time prevent a stale ticket from ever moving an unrelated replacement.
struct TemporaryItemLocation: Codable, Equatable {
    let windowID: Int
    let pid: pid_t
    let launchedAt: TimeInterval?
    let sectionRaw: Int
    let leftNeighbour: Int?
    let rightNeighbour: Int?

    var section: BarSection? { BarSection(rawValue: sectionRaw) }

    init(item: BarItem, snapshot: BarSnapshot, launchedAt: TimeInterval?) {
        windowID = item.windowID
        pid = item.pid
        self.launchedAt = launchedAt
        sectionRaw = item.section.rawValue
        let peers = snapshot.items(in: item.section).sorted { $0.frame.minX < $1.frame.minX }
        let index = peers.firstIndex { $0.windowID == item.windowID }
        leftNeighbour = index.flatMap { $0 > 0 ? peers[$0 - 1].windowID : nil }
        rightNeighbour = index.flatMap { $0 + 1 < peers.count ? peers[$0 + 1].windowID : nil }
    }

    func matches(_ item: BarItem, launchedAt currentLaunch: TimeInterval?) -> Bool {
        guard item.windowID == windowID, item.pid == pid,
              section == .hidden || section == .alwaysHidden else { return false }
        if let launchedAt { return currentLaunch.map { abs($0 - launchedAt) < 0.01 } ?? false }
        return true
    }

    func destination(in snapshot: BarSnapshot, alwaysEnabled: Bool) -> ItemMoveDestination? {
        guard let section, section != .shown else { return nil }
        let destinationSection: BarSection = section == .alwaysHidden && !alwaysEnabled ? .hidden : section
        if let rightNeighbour, let neighbour = snapshot.item(rightNeighbour), neighbour.section == destinationSection {
            return ItemMoveDestination(windowID: rightNeighbour, side: .before)
        }
        if let leftNeighbour, let neighbour = snapshot.item(leftNeighbour), neighbour.section == destinationSection {
            return ItemMoveDestination(windowID: leftNeighbour, side: .after)
        }
        let boundary = destinationSection == .alwaysHidden ? snapshot.anchors?.sepID : snapshot.anchors?.pusherID
        return boundary.map { ItemMoveDestination(windowID: $0, side: .before) }
    }
}

/// Pure policy, independent of timers and WindowServer, so delayed menus and
/// action-only status items can be covered by deterministic regression tests.
struct RevealDismissalPolicy {
    private(set) var sawInterface = false
    private var quietSamples = 0

    mutating func shouldRestore(elapsed: TimeInterval, interfaceOpen: Bool) -> Bool {
        if interfaceOpen { sawInterface = true; quietSamples = 0; return false }
        guard elapsed >= (sawInterface ? 0.6 : 1.8) else { return false }
        quietSamples += 1
        return quietSamples >= 2
    }
}

/// At most ONE hidden icon is ever brought into the shown area. Neither hidden
/// divider shrinks, and neither layout editing nor the expand-all path is used.
final class SingleItemPresenter {
    private struct Request { let windowID: Int; let name: String }
    private static var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BarButler", isDirectory: true)
            .appendingPathComponent("temporary-item.json")
    }
    private weak var owner: StatusBarController?
    private var location: TemporaryItemLocation?
    private var pending: Request?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var openedAt = Date.distantPast
    private var nextRetry = Date.distantPast
    private var dismissal = RevealDismissalPolicy()
    private var reportedFailure = false
    private var baselineWindows = Set<Int>()

    var isActive: Bool { location != nil || task != nil || pending != nil }
    var summary: String { location.map { "#\($0.windowID) return=\($0.sectionRaw)" } ?? (isActive ? "preparing" : "none") }

    init(owner: StatusBarController) {
        self.owner = owner
        if let data = try? Data(contentsOf: Self.recoveryURL) {
            location = try? JSONDecoder().decode(TemporaryItemLocation.self, from: data)
        }
        baselineWindows = Self.onscreenWindowIDs()
    }

    deinit { timer?.invalidate(); task?.cancel() }

    func resume() { ensureTimer() }

    func suspend() {
        pending = nil
        task?.cancel()
        timer?.invalidate()
        timer = nil
        // Keep the return ticket. Restoration resumes only after wake/unlock.
    }

    func open(windowID: Int, name: String) {
        guard let owner else { return }
        guard AXPresser.trusted else {
            Toast.show(L.floatNeedAX.s, kind: .warning, near: owner.arrowScreenFrame)
            AXPresser.promptForPermission()
            return
        }
        guard SystemMonitor.shared.canPostEvents else {
            Toast.show(L.moveLocked.s, kind: .warning, near: owner.arrowScreenFrame)
            return
        }
        guard owner.canPresentSingleItem, task != nil || !ItemMover.isMoving else {
            Toast.show(L.moveBusy.s, kind: .warning, near: owner.arrowScreenFrame)
            return
        }
        pending = Request(windowID: windowID, name: name) // Latest click wins; no overlapping drags.
        if task == nil, !interfaceOpen { pump() }
        ensureTimer()
    }

    /// UI and layout memory see the item's original section during its visit.
    func logicalSnapshot(_ snapshot: BarSnapshot) -> BarSnapshot {
        guard let location, let section = location.section else { return snapshot }
        return BarSnapshot(anchors: snapshot.anchors, items: snapshot.items.map { item in
            guard item.windowID == location.windowID, item.pid == location.pid else { return item }
            return item.inSection(section)
        })
    }

    private func ensureTimer() {
        guard isActive else { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.06
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard task == nil, let owner, SystemMonitor.shared.canPostEvents,
              SystemMonitor.shared.isStable, !ItemMover.isMoving, Date() >= nextRetry else { return }
        if let location {
            let snapshot = owner.snapshot(details: false)
            guard snapshot.anchors != nil else { return }
            if snapshot.item(location.windowID) == nil, AXPresser.bounds(windowID: location.windowID) != nil { return }
            guard let item = snapshot.item(location.windowID), valid(location, item: item) else {
                clearLocation(); if pending != nil { pump() }; return
            }
            let open = interfaceOpen
            if !open, pending != nil { pump(); return }
            if dismissal.shouldRestore(elapsed: Date().timeIntervalSince(openedAt), interfaceOpen: open) { pump() }
        } else if pending != nil { pump() } else { ensureTimer() }
    }

    private func pump() {
        guard task == nil, let owner else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.ensureTimer() }
            do {
                if self.location != nil { try await self.restore(via: owner) }
                guard self.location == nil else { return }
                try Task.checkCancellation()
                guard let request = self.pending else { return }
                self.pending = nil
                try await self.present(request, via: owner)
            } catch {
                self.nextRetry = Date().addingTimeInterval(2)
                Log.event("single-item interaction: \(error)")
                if !Task.isCancelled, !self.reportedFailure {
                    self.reportedFailure = true
                    Toast.show(L.singleItemFailed.s, kind: .warning, near: owner.arrowScreenFrame)
                }
            }
        }
    }

    @MainActor private func present(_ request: Request, via owner: StatusBarController) async throws {
        try Task.checkCancellation()
        guard SystemMonitor.shared.canPostEvents else { throw ItemMover.Failure.locked }
        guard owner.canPresentSingleItem, !ItemMover.isMoving else { throw ItemMover.Failure.busy }
        // A panel may also be opened while the menu bar was manually expanded.
        // Collapse it first; the one requested item is the only temporary addition.
        if !owner.collapsed {
            owner.setCollapsed(true, reason: .other)
            for _ in 0..<20 where !owner.collapsed { try await Task.sleep(nanoseconds: 80_000_000) }
            guard owner.collapsed else { throw ItemMover.Failure.busy }
        }
        var snapshot = owner.snapshot(details: false)
        guard let item = snapshot.item(request.windowID) else { throw ItemMover.Failure.notFound }
        if item.section != .shown {
            guard item.movable, let toggle = snapshot.anchors?.toggleID else { throw ItemMover.Failure.unmovable }
            let ticket = TemporaryItemLocation(item: item, snapshot: snapshot, launchedAt: launchTime(item.pid))
            let file = Self.recoveryURL
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ticket).write(to: file, options: .atomic)
            location = ticket
            reportedFailure = false
            try await ItemMover.shared.moveIsolated(windowID: item.windowID,
                to: ItemMoveDestination(windowID: toggle, side: .after), via: owner)
        }
        var last: CGRect?
        for _ in 0..<25 {
            try Task.checkCancellation()
            if let frame = AXPresser.onscreenBounds(windowID: item.windowID), frame == last {
                baselineWindows = Self.onscreenWindowIDs()
                guard await AXPresser.click(windowID: item.windowID) else { throw ItemMover.Failure.notVisible }
                openedAt = Date()
                dismissal = RevealDismissalPolicy()
                Log.event("single-item opened: \(request.name) #\(item.windowID); other icons stayed hidden")
                return
            }
            last = AXPresser.onscreenBounds(windowID: item.windowID)
            try await Task.sleep(nanoseconds: 80_000_000)
            snapshot = owner.snapshot(details: false)
            guard snapshot.item(item.windowID) != nil else { throw ItemMover.Failure.notFound }
        }
        throw ItemMover.Failure.notVisible // Never fall back to expanding all icons.
    }

    @MainActor private func restore(via owner: StatusBarController) async throws {
        guard let ticket = location else { return }
        let snapshot = owner.snapshot(details: false)
        guard snapshot.anchors != nil else { throw ItemMover.Failure.notFound }
        if snapshot.item(ticket.windowID) == nil, AXPresser.bounds(windowID: ticket.windowID) != nil { throw ItemMover.Failure.notFound }
        guard let item = snapshot.item(ticket.windowID), valid(ticket, item: item) else { clearLocation(); return }
        guard !interfaceOpen, SystemMonitor.shared.canPostEvents else { return }
        if item.section != ticket.section || item.onScreen {
            guard let destination = ticket.destination(in: snapshot, alwaysEnabled: Prefs.shared.alwaysHiddenEnabled) else {
                throw ItemMover.Failure.notFound
            }
            try await ItemMover.shared.moveIsolated(windowID: item.windowID, to: destination, via: owner)
        }
        Log.event("single-item restored: #\(ticket.windowID)")
        clearLocation()
    }

    private func clearLocation() {
        location = nil
        try? FileManager.default.removeItem(at: Self.recoveryURL)
        baselineWindows.removeAll()
        reportedFailure = false
        nextRetry = .distantPast
        owner?.singleItemInteractionDidEnd()
        ensureTimer()
    }

    private func launchTime(_ pid: pid_t) -> TimeInterval? {
        NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSince1970
    }

    private func valid(_ ticket: TemporaryItemLocation, item: BarItem) -> Bool {
        ticket.matches(item, launchedAt: launchTime(item.pid))
    }

    private static func onscreenWindowIDs() -> Set<Int> {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    private var interfaceOpen: Bool {
        guard let owner else { return false }
        if owner.isStatusItemUIOpen { return true }
        guard let location else { return false }
        // Some apps use an ordinary borderless window, not NSMenu/NSPopover.
        // Only NEW windows belonging to the clicked process and touching the
        // menu bar count; its pre-existing document windows cannot pin the icon.
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let bands = ScreenGeometry.menuBarBottomBandsCG()
        return list.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? Int) == Int(location.pid),
                  let id = window[kCGWindowNumber as String] as? Int, !baselineWindows.contains(id),
                  let data = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: data), frame.width >= 80, frame.height >= 50 else { return false }
            return bands.contains { $0.contains(frame.minY) }
        }
    }
}

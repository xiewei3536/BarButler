import AppKit

/// 代為移動選單列圖示：模擬「按住 ⌘ 拖曳」。
///
/// 實測（macOS 15）：⌘ 按下必須落在圖示「真正顯示在畫面上」的位置，畫面外（已收合）的圖示拖不動，
/// 所以移動前要先展開、必要時借用選單列騰出空間，等圖示真的出現再拖。放開位置落在某個項目的
/// 左半邊就插到它左側、右半邊就插到右側；移動後 macOS 會重寫所有項目的 Preferred Position。
@MainActor
final class ItemMover {
    static let shared = ItemMover()
    private(set) var busy = false {
        didSet { Self.isMoving = busy }
    }
    /// 給非 MainActor 的程式碼查詢（實際上都在主執行緒存取）
    nonisolated(unsafe) static var isMoving = false
    /// 即將睡眠等情況要求中止進行中的移動
    nonisolated(unsafe) static var cancelRequested = false

    enum Failure: Error {
        case permission, locked, busy, notFound, unmovable, notVisible, didNotMove, collateral, cancelled
    }

    /// 把 windowID 對應的圖示移到指定區塊；成功或原本就在該區塊都算成功。
    /// interactive = 使用者點擊觸發（可以借用選單列）；背景自動歸位時為 false
    func move(windowID: Int, to dest: BarSection, via c: StatusBarController, interactive: Bool = true) async throws {
        guard AXPresser.trusted else { throw Failure.permission }
        guard SystemMonitor.shared.canPostEvents else { throw Failure.locked }
        guard !busy else { throw Failure.busy }
        busy = true
        Self.cancelRequested = false
        defer { busy = false }

        guard let item = c.snapshot().item(windowID) else { throw Failure.notFound }
        guard item.movable else { throw Failure.unmovable }
        if item.section == dest { return }
        Log.event("move \(item.label) #\(windowID): \(item.section) → \(dest)")

        c.beginEditing()
        defer { c.endEditing() }

        for attempt in 1...3 {
            try checkCancelled()
            guard let (src, anchors) = await waitUntilVisible(windowID, dest: dest, c: c) else {
                try checkCancelled()
                Log.event("move \(item.label): never became visible (attempt \(attempt))")
                if interactive, attempt == 1, !c.isBorrowingMenuBar, NSApp.activationPolicy() != .regular {
                    c.borrowMenuBar() // 最後手段（非使用者點擊當下可能被系統拒絕）
                    continue
                }
                throw Failure.notVisible
            }
            guard let (drop, targetWin) = dropPoint(for: dest, anchors: anchors) else { throw Failure.notVisible }
            // 其他圖示目前的區塊：移動後若有別的圖示跟著換區，代表拖錯了（排版正好在變動）
            let before = Dictionary(c.snapshot(details: false).items.map { ($0.windowID, $0.section) },
                                    uniquingKeysWith: { a, _ in a })
            guard await drag(src, to: drop, targetWindow: targetWin, steps: [8, 14, 3][attempt - 1]) else {
                try checkCancelled()
                Log.event("move \(item.label): icon shifted right before the drag; retrying")
                continue
            }
            // 等 macOS 重新排版
            for _ in 0..<6 {
                await sleep(0.12)
                let after = c.snapshot(details: false)
                guard let now = after.item(windowID), now.section == dest else { continue }
                let collateral = after.items.filter { other in
                    guard other.windowID != windowID, let was = before[other.windowID] else { return false }
                    return was != other.section
                }
                if !collateral.isEmpty {
                    Log.event("move \(item.label): other icons changed section too (\(collateral.map(\.label).joined(separator: ", "))) — stopping")
                    throw Failure.collateral
                }
                Log.event("move \(item.label) ✓ \(dest) (attempt \(attempt))")
                return
            }
            Log.event("move \(item.label): not in \(dest) after attempt \(attempt)")
        }
        throw Failure.didNotMove
    }

    /// 移動失敗時給使用者看的說明
    static func message(for error: Error, label: String) -> String {
        switch error as? Failure {
        case .permission: return L.moveNeedsAX.s
        case .locked, .cancelled: return L.moveLocked.s
        case .busy: return L.moveBusy.s
        case .unmovable: return L.itemLocked.s
        case .notFound: return L.moveGone.f(label)
        default: return L.moveFailed.f(label)
        }
    }

    // MARK: - 細節

    private func checkCancelled() throws {
        if Self.cancelRequested || !SystemMonitor.shared.canPostEvents { throw Failure.cancelled }
    }

    /// 輪詢直到來源圖示與目標錨點都真的在畫面上、且位置連續兩次不變（最多約 2 秒）
    private func waitUntilVisible(_ id: Int, dest: BarSection, c: StatusBarController) async -> (BarItem, BarAnchors)? {
        var stable = 0
        var last: CGRect?
        for _ in 0..<25 {
            if Self.cancelRequested { return nil }
            let snap = c.snapshot(details: false)
            if let it = snap.item(id), let a = snap.anchors, it.onScreen, a.toggleOnScreen,
               ScreenGeometry.xOnSomeScreen(it.frame.midX), ScreenGeometry.xOnSomeScreen(a.toggle.midX),
               dropPoint(for: dest, anchors: a).map({ ScreenGeometry.xOnSomeScreen($0.0.x) }) == true {
                stable = (last == it.frame) ? stable + 1 : 1   // 避免排版動畫途中出手
                last = it.frame
                if stable >= 2 { return (it, a) }
            } else {
                stable = 0
                last = nil
            }
            await sleep(0.08)
        }
        return nil
    }

    /// 放開位置：常駐 = ‹ 的右半邊；收合 = pusher 的左緣；永久隱藏 = 分隔線的左緣
    private func dropPoint(for dest: BarSection, anchors a: BarAnchors) -> (CGPoint, Int)? {
        switch dest {
        case .shown:
            return (CGPoint(x: a.toggle.maxX - 2, y: a.toggle.midY), a.toggleID)
        case .hidden:
            guard let p = a.pusher, let id = a.pusherID else { return nil }
            return (CGPoint(x: p.minX + 2, y: p.midY), id)
        case .alwaysHidden:
            guard let s = a.sep, let id = a.sepID else { return nil }
            return (CGPoint(x: s.minX + 2, y: s.midY), id)
        }
    }

    /// 實測：只送 1～2 個拖曳事件常常「放不進去」；分段移動、在落點稍停再放開最可靠。
    /// 按下前再確認一次來源圖示還在原處（排版可能剛好在變），不在就不按，回傳 false。
    private func drag(_ src: BarItem, to drop: CGPoint, targetWindow: Int, steps: Int) async -> Bool {
        guard !Self.cancelRequested, SystemMonitor.shared.canPostEvents,
              let fresh = AXPresser.onscreenBounds(windowID: src.windowID),
              abs(fresh.midX - src.frame.midX) < 2, abs(fresh.width - src.frame.width) < 2 else { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        let permit: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source?.setLocalEventsFilterDuringSuppressionState(permit, state: .eventSuppressionStateRemoteMouseDrag)
        source?.setLocalEventsFilterDuringSuppressionState(permit, state: .eventSuppressionStateSuppressionInterval)
        source?.localEventsSuppressionInterval = 0

        let original = CGEvent(source: nil)?.location
        let display = CGMainDisplayID()
        CGDisplayHideCursor(display)
        defer {
            if let o = original { CGWarpMouseCursorPosition(o) }
            CGDisplayShowCursor(display)
        }

        let start = CGPoint(x: fresh.midX, y: fresh.midY)
        post(.leftMouseDown, at: start, window: src.windowID, pid: src.pid, source: source)
        await sleep(0.06)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + (drop.x - start.x) * t, y: start.y + (drop.y - start.y) * t)
            post(.leftMouseDragged, at: p, window: src.windowID, pid: src.pid, source: source)
            await sleep(0.022)
        }
        post(.leftMouseDragged, at: drop, window: targetWindow, pid: src.pid, source: source)
        await sleep(0.06)
        // 一旦按下就一定要放開（即使途中被要求中止），否則系統會以為還在拖曳
        post(.leftMouseUp, at: drop, window: targetWindow, pid: src.pid, source: source)
        await sleep(0.08)
        return true
    }

    private func post(_ type: CGEventType, at p: CGPoint, window: Int, pid: pid_t, source: CGEventSource?) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.flags = .maskCommand
        e.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        e.setIntegerValueField(.mouseEventClickState, value: 1)
        e.post(tap: .cgSessionEventTap)
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}

import AppKit

/// Delivers an event to one status-item window without exposing its hidden neighbours.
/// Both WindowServer and the owning process must see the same event. A short-lived,
/// token-filtered relay routes only our event; ordinary input is never swallowed.
final class DirectedMenuBarEvent {
    enum Failure: Error { case unavailable, timedOut }

    private let event: CGEvent
    private let pid: pid_t
    private let token = Int64.random(in: 1...Int64.max)
    private var processTap: CFMachPort?
    private var sessionTap: CFMachPort?
    private var sources: [CFRunLoopSource] = []
    private var timeout: DispatchWorkItem?
    private var continuation: CheckedContinuation<Void, Error>?

    init(event: CGEvent, pid: pid_t) {
        self.event = event
        self.pid = pid
        event.setIntegerValueField(.eventSourceUserData, value: token)
    }

    func deliver() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let context = Unmanaged.passUnretained(self).toOpaque()
            let mask = CGEventMask(1) << event.type.rawValue
            processTap = CGEvent.tapCreateForPid(
                pid: pid, place: .tailAppendEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: { _, type, received, context in
                    guard let context else { return Unmanaged.passUnretained(received) }
                    let relay = Unmanaged<DirectedMenuBarEvent>.fromOpaque(context).takeUnretainedValue()
                    guard type == relay.event.type,
                          received.getIntegerValueField(.eventSourceUserData) == relay.token,
                          let port = relay.processTap, CGEvent.tapIsEnabled(tap: port) else {
                        return Unmanaged.passUnretained(received)
                    }
                    CGEvent.tapEnable(tap: port, enable: false)
                    relay.event.post(tap: .cgSessionEventTap)
                    return nil // Only the first copy of our synthetic event is consumed.
                }, userInfo: context)
            sessionTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: { _, type, received, context in
                    guard let context else { return Unmanaged.passUnretained(received) }
                    let relay = Unmanaged<DirectedMenuBarEvent>.fromOpaque(context).takeUnretainedValue()
                    if type == relay.event.type,
                       received.getIntegerValueField(.eventSourceUserData) == relay.token {
                        relay.event.postToPid(relay.pid)
                        relay.finish(.success(()))
                    }
                    return Unmanaged.passUnretained(received)
                }, userInfo: context)
            guard let processTap, let sessionTap else { finish(.failure(Failure.unavailable)); return }
            for port in [processTap, sessionTap] {
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                    finish(.failure(Failure.unavailable)); return
                }
                sources.append(source)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            let work = DispatchWorkItem { [weak self] in self?.finish(.failure(Failure.timedOut)) }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            event.postToPid(pid)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil // Timeouts and callbacks must never resume twice.
        timeout?.cancel()
        timeout = nil
        for port in [processTap, sessionTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        sources.removeAll()
        processTap = nil
        sessionTap = nil
        continuation.resume(with: result)
    }

    /// WindowServer's window-number field is not named by the SDK. Keep the
    /// compatibility detail here, and fail closed if event creation is unavailable.
    static func make(_ type: CGEventType, point: CGPoint, windowID: Int,
                     pid: pid_t, source: CGEventSource, command: Bool = false) -> CGEvent? {
        guard let windowField = CGEventField(rawValue: 0x33),
              let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        event.setIntegerValueField(windowField, value: Int64(windowID))
        return event
    }
}

struct ItemMoveDestination: Equatable {
    enum Side: String, Codable { case before, after }
    let windowID: Int
    let side: Side

    func point(in frame: CGRect) -> CGPoint {
        CGPoint(x: side == .before ? frame.minX + 1 : frame.maxX - 1, y: frame.midY)
    }
}

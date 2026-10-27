import AppKit
import Carbon.HIToolbox

/// 系統狀態：睡眠／喚醒、螢幕睡眠、螢幕組態變動、使用者切換、鎖定畫面。
///
/// 喚醒與換螢幕期間狀態列會暫時亂排（合蓋外接螢幕的 Mac 在暗喚醒時甚至會短暫切到內建螢幕），
/// 所有「依幾何位置修正」的邏輯都必須等系統穩定後才執行——v1.3.2 就是在暗喚醒時誤判 ‹ 出界，
/// 把位置紀錄全部刪掉，喚醒後 ‹ 跑到最左邊、什麼都藏不住。
final class SystemMonitor {
    static let shared = SystemMonitor()

    private(set) var systemAsleep = false
    private(set) var screensAsleep = false
    private(set) var sessionActive = true
    private(set) var screenLocked = false
    private(set) var lastTransition: (reason: String, at: Date)?
    private var quietUntil = Date.distantPast
    private var settleWork: DispatchWorkItem?
    private var settleAttempts = 0
    private var settledHandlers: [(String) -> Void] = []
    private var sleepHandlers: [() -> Void] = []
    private var started = false
    private var inputCountAtSleep: UInt32?
    private static let anyInput = CGEventType(rawValue: ~0)!

    /// 醒著、螢幕亮著、組態變動已平息——只有這時才可以依幾何位置做判斷或修正
    var isStable: Bool {
        !systemAsleep && !screensAsleep && sessionActive && Date() >= quietUntil
            && !NSScreen.screens.isEmpty && CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    /// 可以送出合成滑鼠事件（未鎖定、沒有其他程式開著安全輸入）
    var canPostEvents: Bool { isStable && !screenLocked && !IsSecureEventInputEnabled() }

    /// 系統穩定下來（喚醒、換螢幕、解鎖之後）時呼叫
    func onSettled(_ h: @escaping (String) -> Void) { settledHandlers.append(h) }
    /// 即將睡眠時呼叫
    func onWillSleep(_ h: @escaping () -> Void) { sleepHandlers.append(h) }

    func start() {
        guard !started else { return }
        started = true
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let s = self else { return }
            s.systemAsleep = true
            s.inputCountAtSleep = CGEventSource.counterForEventType(.combinedSessionState, eventType: Self.anyInput)
            s.settleWork?.cancel()
            Log.event("system will sleep")
            s.sleepHandlers.forEach { $0() }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = false
            self?.transition("didWake", quiet: 4)
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.inputCountAtSleep = CGEventSource.counterForEventType(.combinedSessionState, eventType: Self.anyInput)
            Log.event("screens did sleep")
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.transition("screensDidWake", quiet: 3)
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false
            Log.event("session resigned")
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true
            self?.transition("sessionActive", quiet: 3)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.transition("screenParameters", quiet: 2.5)
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            Log.event("screen locked")
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.transition("unlocked", quiet: 2)
        }
    }

    /// 進入過渡期：quiet 秒內不做任何幾何修正，平息後通知
    func transition(_ reason: String, quiet: TimeInterval) {
        quietUntil = max(quietUntil, Date().addingTimeInterval(quiet))
        lastTransition = (reason, Date())
        settleAttempts = 0
        Log.event("transition: \(reason) (quiet \(quiet)s) screens=\(NSScreen.screens.count)")
        scheduleSettle(after: quiet + 0.3)
    }

    /// 使用者顯然在操作（點了 ‹、按了快捷鍵）——若錯過了喚醒通知，以此認定系統醒著
    func noteUserActivity() {
        guard systemAsleep || screensAsleep else { return }
        Log.event("user activity while marked asleep → assume awake")
        systemAsleep = false
        screensAsleep = false
        transition("userActivity", quiet: 1)
    }

    /// 看門狗用：若標記為睡眠、但睡眠之後「確實」有新的輸入事件，表示其實醒著（錯過了通知）。
    /// 不能只看閒置秒數：它可能不含睡眠時間，從選單按下「睡眠」後的暗喚醒會被誤判成醒著。
    func reconcile() {
        guard systemAsleep || screensAsleep, let before = inputCountAtSleep else { return }
        let now = CGEventSource.counterForEventType(.combinedSessionState, eventType: Self.anyInput)
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        if now != before, idle < 10, CGDisplayIsAsleep(CGMainDisplayID()) == 0 { noteUserActivity() }
    }

    private func scheduleSettle(after t: TimeInterval) {
        settleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.settle() }
        settleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
    }

    private func settle() {
        guard isStable else {
            settleAttempts += 1
            if settleAttempts < 60 { scheduleSettle(after: 1.5) } // 最多再等 90 秒
            return
        }
        let reason = lastTransition?.reason ?? "?"
        Log.event("settled after \(reason)")
        settledHandlers.forEach { $0(reason) }
    }

    var summary: String {
        "stable=\(isStable) asleep=\(systemAsleep) screensAsleep=\(screensAsleep) session=\(sessionActive) locked=\(screenLocked) secureInput=\(IsSecureEventInputEnabled()) screens=\(NSScreen.screens.count)"
            + (lastTransition.map { " last=\($0.reason)@\(Self.timeFmt.string(from: $0.at))" } ?? "")
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()
}

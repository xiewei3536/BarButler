import AppKit
import Sparkle

/// Sparkle 自動更新（僅在完整打包、Info.plist 含 SUFeedURL 時啟用；開發模式自動停用）
final class UpdaterManager: NSObject, SPUStandardUserDriverDelegate {
    static let shared = UpdaterManager()
    private var controller: SPUStandardUpdaterController?

    var available: Bool { controller != nil }
    var updater: SPUUpdater? { controller?.updater }

    private override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: - 溫和提醒（背景 App 排程檢查到新版本時，先以提示帶到前景，避免更新視窗默默藏在後面）

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        Toast.show(L.toastUpdateAvailable.f(update.displayVersionString), kind: .info)
        NSApp.activate(ignoringOtherApps: true)
    }
}

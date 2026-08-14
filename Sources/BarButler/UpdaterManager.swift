import AppKit
import Sparkle

/// Sparkle 自動更新（僅在完整打包、Info.plist 含 SUFeedURL 時啟用；開發模式自動停用）
final class UpdaterManager {
    static let shared = UpdaterManager()
    private var controller: SPUStandardUpdaterController?

    var available: Bool { controller != nil }
    var updater: SPUUpdater? { controller?.updater }

    private init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

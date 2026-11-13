import SwiftUI

#if QUOTA_SPARKLE
import Sparkle

@MainActor
final class ReleaseUpdates {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )

    let canCheck = true

    func start() {
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func check() {
        controller.checkForUpdates(nil)
    }
}
#else
@MainActor
final class ReleaseUpdates {
    let canCheck = false
    func start() {}
    func check() {}
}
#endif

struct ReleaseUpdateControls: View {
    let updates: ReleaseUpdates

    var body: some View {
        Button("Check for Updates") { updates.check() }
    }
}

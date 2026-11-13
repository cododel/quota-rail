import Foundation

#if QUOTA_RELEASE
import OSLog
import ServiceManagement
#endif

enum LoginItem {
    @MainActor
    static func registerOnFirstLaunch() {
        #if QUOTA_RELEASE
        guard Bundle.main.bundleIdentifier == "com.cododel.quota-rail",
              !CommandLine.arguments.contains("--demo"),
              !CommandLine.arguments.contains("--full-demo") else { return }

        let defaults = UserDefaults.standard
        let key = "quotaRail.initialLoginItemRegistrationHandled"
        guard !defaults.bool(forKey: key) else { return }

        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                Logger(subsystem: "com.cododel.quota-rail", category: "LoginItem")
                    .error("Could not register login item: \(error.localizedDescription, privacy: .public)")
                return
            }
        case .enabled, .requiresApproval:
            break
        @unknown default:
            return
        }

        // Remember the initial setup even if the user later disables the login item.
        defaults.set(true, forKey: key)
        #endif
    }
}

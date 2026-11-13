import Foundation

enum AppResources {
    static var directory: URL {
        if Bundle.main.bundleIdentifier == "com.cododel.quota-rail",
           let resources = Bundle.main.resourceURL {
            return resources
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    static func migratePreferences() {
        guard let domain = Bundle.main.bundleIdentifier, domain == "com.cododel.quota-rail" else { return }
        let defaults = UserDefaults.standard
        let marker = "quotaRail.migratedLegacyPreferences"
        var current = defaults.persistentDomain(forName: domain) ?? [:]
        guard current[marker] == nil else { return }
        let legacy = defaults.persistentDomain(forName: "projector-overlay") ?? [:]
        for key in ["projector.overlay.hiddenSubscriptions", "projector.overlay.fullDemo"] {
            if current[key] == nil { current[key] = legacy[key] }
        }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: domain)
    }
}

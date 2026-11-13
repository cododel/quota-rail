import Foundation

enum AppResources {
    static var directory: URL {
        if Bundle.main.bundleIdentifier == "com.cododel.quota-rail",
           let resources = Bundle.main.resourceURL {
            return resources
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }
}

import Foundation

enum AppResources {
    static var directory: URL {
        if Bundle.main.bundleIdentifier == "com.cododel.quota-rail",
           let resources = Bundle.main.resourceURL {
            return resources
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    static func providerHelper(_ name: String) -> URL {
        let adjacent = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: adjacent.path) {
            return adjacent
        }
        return directory.appendingPathComponent("Sources/Providers").appendingPathComponent(name)
    }
}

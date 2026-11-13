import Foundation

struct ProviderStatus: Sendable {
    let name: String
    let cliInstalled: Bool
    var authorization = "Unknown"
    var subscription = "Unknown"
    var quotaAvailable = false

    var showsInSettings: Bool {
        cliInstalled && authorization == "Signed in"
    }

    var planLabel: String? {
        switch subscription {
        case "Unknown", "API profile", "Shared weekly access", "Go access confirmed": nil
        default: subscription
        }
    }

    init(_ name: String, executable: String, extraPaths: [String] = []) {
        self.name = name
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + extraPaths + [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        cliInstalled = paths.contains {
            $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0 + "/" + executable)
        }
    }

    static func read<Quota>(_ name: String, executable: String, extraPaths: [String] = [],
                            fetch: (inout Self) async -> Quota?) async -> (Quota?, Self) {
        var status = Self(name, executable: executable, extraPaths: extraPaths)
        let quota = await fetch(&status)
        status.quotaAvailable = quota != nil
        if quota != nil, status.authorization == "Unknown" {
            status.authorization = "Signed in"
        }
        return (quota, status)
    }
}

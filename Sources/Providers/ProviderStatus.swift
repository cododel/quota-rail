import Foundation

struct ProviderStatus: Sendable {
    let name: String
    let cliInstalled: Bool
    var authorization = "Unknown"
    var subscription = "Unknown"
    var quotaAvailable = false

    var showsInSettings: Bool {
        cliInstalled
    }

    var needsSignIn: Bool {
        switch authorization {
        case "Signed out", "Sign-in required", "Credentials rejected": true
        default: false
        }
    }

    var unavailableQuotaLabel: String {
        needsSignIn ? "Sign-in required" : "No quota"
    }

    static func settingsOrder(_ providers: [Self], quotaOrder: [String]) -> [Self] {
        let installed = providers.filter(\.showsInSettings)
        let withQuota = quotaOrder.compactMap { name in installed.first { $0.name == name } }
        let withoutQuota = installed.filter { !quotaOrder.contains($0.name) }
        return withQuota + withoutQuota.filter { !$0.needsSignIn } + withoutQuota.filter(\.needsSignIn)
    }

    var planLabel: String? {
        switch subscription {
        case "Unknown", "API profile", "Shared weekly access", "Go access confirmed": nil
        default: subscription
        }
    }

    init(_ name: String, executable: String, extraPaths: [String] = []) {
        self.name = name
        cliInstalled = Self.executablePath(executable, extraPaths: extraPaths) != nil
    }

    static func executablePath(_ executable: String, extraPaths: [String] = []) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + extraPaths + [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.filter { $0.hasPrefix("/") }.map { $0 + "/" + executable }
            .first(where: FileManager.default.isExecutableFile(atPath:))
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

struct ProviderQuotaSnapshot<Quota> {
    private(set) var quota: Quota?
    private(set) var status: ProviderStatus?
    private(set) var lastUpdated: Date?

    var isStale: Bool { quota != nil && status?.quotaAvailable == false }

    mutating func update(_ fetched: Quota?, status current: ProviderStatus, now: Date = Date()) {
        var status = current
        status.quotaAvailable = fetched != nil
        switch current.authorization {
        case "Signed out", "Sign-in required", "Credentials rejected", "API key", "API profile":
            quota = nil
            lastUpdated = nil
            status.quotaAvailable = false
        default:
            if !current.cliInstalled && fetched == nil {
                quota = nil
                lastUpdated = nil
            } else if let fetched {
                quota = fetched
                lastUpdated = now
            } else if quota != nil {
                if status.authorization == "Unknown", let previous = self.status {
                    status.authorization = previous.authorization
                }
                if status.subscription == "Unknown", let previous = self.status {
                    status.subscription = previous.subscription
                }
            }
        }
        self.status = status
    }
}

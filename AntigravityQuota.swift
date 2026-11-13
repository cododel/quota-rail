import Foundation

struct AntigravityQuota: Sendable {
    let gemini: CodexQuota
    let thirdParty: CodexQuota

    static func parse(_ data: Data, now: Date = Date()) -> Self? {
        guard let buckets = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        let formatter = ISO8601DateFormatter()
        func quota(_ prefix: String) -> CodexQuota? {
            var windows: [CodexQuota.LimitWindow] = []
            for (suffix, minutes) in [("5h", 300), ("weekly", 10_080)] {
                guard let bucket = buckets["\(prefix)-\(suffix)"],
                      bucket["disabled"] as? Bool != true,
                      let fraction = bucket["remaining_fraction"] as? Double,
                      fraction.isFinite, (0...1).contains(fraction),
                      let resetText = bucket["reset_time"] as? String else { return nil }
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fractional = formatter.date(from: resetText)
                formatter.formatOptions = [.withInternetDateTime]
                guard let reset = fractional ?? formatter.date(from: resetText), reset > now else { return nil }
                windows.append(.init(id: suffix, remaining: Int((fraction * 100).rounded()), minutes: minutes, reset: reset))
            }
            let first = windows[0]
            return CodexQuota(remaining: first.remaining, windowMinutes: first.minutes, reset: first.reset,
                              resetCredits: nil, availableResets: [], usageCreditBalance: nil,
                              unlimitedUsageCredits: false, additionalWindows: Array(windows.dropFirst()))
        }
        guard let gemini = quota("gemini"), let thirdParty = quota("3p") else { return nil }
        return Self(gemini: gemini, thirdParty: thirdParty)
    }

    static func read() -> Self? {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin"]
        guard let executable = folders.filter({ $0.hasPrefix("/") }).map({ $0 + "/agy" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let helper = AppResources.directory.appendingPathComponent("agy-quota.py")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [helper.path, executable]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // The helper bounds the CLI lifetime and owns cleanup of its entire process group.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 65_536 else { return nil }
        return parse(data)
    }
}

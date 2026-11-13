import Foundation

struct ClaudeQuota {
    static func parse(_ data: Data, now: Date = Date()) -> CodexQuota? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let source = raw["rate_limits"] as? [String: Any] ?? raw
        let formatter = ISO8601DateFormatter()
        let windows = [("five_hour", 300), ("seven_day", 10_080)].compactMap { key, minutes -> CodexQuota.LimitWindow? in
            guard let bucket = source[key] as? [String: Any],
                  let used = (bucket["utilization"] ?? bucket["used_percentage"]) as? Double,
                  used.isFinite, (0...100).contains(used),
                  let text = bucket["resets_at"] as? String else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = formatter.date(from: text)
            formatter.formatOptions = [.withInternetDateTime]
            guard let reset = fractional ?? formatter.date(from: text), reset > now else { return nil }
            return .init(id: key, remaining: Int((100 - used).rounded()), minutes: minutes, reset: reset)
        }
        guard let first = windows.first else { return nil }
        return CodexQuota(remaining: first.remaining, windowMinutes: first.minutes, reset: first.reset,
                          resetCredits: nil, availableResets: [], usageCreditBalance: nil,
                          unlimitedUsageCredits: false, additionalWindows: Array(windows.dropFirst()))
    }

    static func read() -> CodexQuota? {
        let helper = AppResources.directory.appendingPathComponent("claude-quota.py")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [helper.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 65_536 else { return nil }
        return parse(data)
    }
}

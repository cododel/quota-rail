import Foundation

struct CodexQuota: Sendable {
    let remaining: Int
    let windowMinutes: Int?
    let reset: Date?
    struct ResetCredit: Identifiable, Sendable {
        let id: String
        let expiresAt: Date?
    }

    let resetCredits: Int?
    let availableResets: [ResetCredit]
    let usageCreditBalance: Decimal?
    let unlimitedUsageCredits: Bool
    var additionalWindows: [LimitWindow] = []

    struct LimitWindow: Identifiable, Sendable {
        let id: String
        let remaining: Int
        let minutes: Int?
        let reset: Date?

        var label: String {
            guard let minutes else { return "Limit" }
            if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)d" }
            if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
            return "\(minutes)m"
        }
    }

    var windows: [LimitWindow] {
        [LimitWindow(id: "primary", remaining: remaining, minutes: windowMinutes, reset: reset)] + additionalWindows
    }

    static func readWindows(_ limits: [String: Any], now: Date = Date()) -> [LimitWindow] {
        ["primary", "secondary"].compactMap { key in
            guard let window = limits[key] as? [String: Any],
                  let used = window["usedPercent"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            let reset = (window["resetsAt"] as? Double).flatMap {
                $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
            }
            if let reset, reset <= now { return nil }
            return LimitWindow(id: key, remaining: Int((100 - used).rounded()),
                               minutes: window["windowDurationMins"] as? Int, reset: reset)
        }
    }

    var usageCreditLabel: String? {
        if unlimitedUsageCredits { return "Usage credits: Unlimited" }
        guard let usageCreditBalance else { return nil }
        // Reference estimate for a USD pack priced at $40 per 1,000 credits.
        let usdPerCredit = Decimal(4) / 100
        let usd = (usageCreditBalance * usdPerCredit).formatted(.currency(code: "USD"))
        return "Usage credits: \(usageCreditBalance.formatted()) (≈\(usd))"
    }

    var label: String {
        guard let windowMinutes else { return "Codex" }
        return "Codex · \(windowMinutes.isMultiple(of: 60) ? "\(windowMinutes / 60)h" : "\(windowMinutes)m")"
    }

    enum Status: String, Error {
        case missing = "Codex CLI not found"
        case signedOut = "Sign in to Codex to see limits"
        case apiProfile = "Current Codex profile has no ChatGPT quota"
        case unavailable = "Codex quota unavailable"
    }

    static func read() -> Result<Self, Status> {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            .filter { $0.hasPrefix("/") }
            + ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
        guard let executable = folders.map({ URL(fileURLWithPath: $0).appendingPathComponent("codex") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            return .failure(.missing)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.unavailable) }
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            timeout.cancel()
        }

        var buffer = Data()
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func request(_ id: Int, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
            try send(["id": id, "method": method, "params": params])
            while true {
                if let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end])
                    buffer.removeSubrange(...end)
                    guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                          response["id"] as? Int == id else { continue }
                    guard let result = response["result"] as? [String: Any] else { throw Status.unavailable }
                    return result
                }
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty, buffer.count + chunk.count <= 1_048_576 else { throw Status.unavailable }
                buffer.append(chunk)
            }
        }

        do {
            _ = try request(1, "initialize", ["clientInfo": ["name": "projector-overlay", "version": "0.1"]])
            try send(["method": "initialized"])
            let auth = try request(2, "account/read", ["refreshToken": false])
            if auth["requiresOpenaiAuth"] as? Bool == false { return .failure(.apiProfile) }
            guard let account = auth["account"] as? [String: Any] else { return .failure(.signedOut) }
            if account["type"] as? String == "apiKey" { return .failure(.apiProfile) }

            let response = try request(3, "account/rateLimits/read")
            let resetBank = response["rateLimitResetCredits"] as? [String: Any]
            let resetCredits = (resetBank?["availableCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            var seenResetIDs = Set<String>()
            let availableResets = (resetBank?["credits"] as? [[String: Any]] ?? [])
                .compactMap { entry -> ResetCredit? in
                    guard entry["status"] as? String == "available",
                          let id = entry["id"] as? String, !id.isEmpty,
                          seenResetIDs.insert(id).inserted else { return nil }
                    let expiration = entry["expiresAt"] as? Double
                    return ResetCredit(id: id, expiresAt: expiration.flatMap {
                        $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
                    })
                }
                .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            guard let limits = response["rateLimits"] as? [String: Any] else { return .failure(.unavailable) }
            let credits = limits["credits"] as? [String: Any]
            let balance = (credits?["balance"] as? String)
                .flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                .flatMap { !$0.isNaN && $0 >= 0 ? $0 : nil }
            let windows = readWindows(limits)
            guard let first = windows.first else { return .failure(.unavailable) }
            return .success(Self(
                remaining: first.remaining, windowMinutes: first.minutes, reset: first.reset,
                resetCredits: resetCredits, availableResets: availableResets,
                usageCreditBalance: balance,
                unlimitedUsageCredits: credits?["unlimited"] as? Bool == true,
                additionalWindows: windows.dropFirst().map {
                    LimitWindow(id: "additional-\($0.id)", remaining: $0.remaining, minutes: $0.minutes, reset: $0.reset)
                }
            ))
        } catch {
            return .failure(.unavailable)
        }
    }
}

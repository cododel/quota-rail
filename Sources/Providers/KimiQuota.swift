import CoreFoundation
import Darwin
import Foundation

enum KimiQuota {
    static let helperFlag = "--kimi-quota-helper"
    static var extraPaths: [String] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code/bin").path]
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        guard status.cliInstalled, !Task.isCancelled, let helper = Bundle.main.executableURL,
              let kimi = ProviderStatus.executablePath("kimi", extraPaths: extraPaths) else { return nil }
        // An exchange can already be rotating OAuth when the UI poll is cancelled.
        let data = await Task.detached { runHelper(helper, kimi: kimi) }.value
        return apply(data, status: &status)
    }

    @MainActor
    static func deferTermination(until refresh: Task<(CodexQuota?, ProviderStatus), Never>?,
                                 reply: @escaping () -> Void) -> Bool {
        guard let refresh else { return false }
        Task {
            _ = await refresh.value
            reply()
        }
        return true
    }

    private static func runHelper(_ executable: URL, kimi: String) -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = [helperFlag, kimi]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    static func handleHelper(_ arguments: [String]) -> Never {
        guard arguments.count == 3, arguments[2].hasPrefix("/") else { exit(2) }
        // The UI can disappear before this helper finishes owning the Kimi process.
        signal(SIGPIPE, SIG_IGN)
        let executable = URL(fileURLWithPath: arguments[2])
        let completed = DispatchSemaphore(value: 0)
        Task.detached {
            if let data = await runLocal(executable: executable) {
                try? FileHandle.standardOutput.write(contentsOf: data)
            }
            completed.signal()
        }
        completed.wait()
        exit(0)
    }

    static func runLocal(executable: URL, startupTimeout: Duration = .seconds(8),
                         requestTimeout: TimeInterval = 180, shutdownTimeout: Duration = .seconds(5)) async -> Data? {
        let process = Process()
        let pipe = Pipe()
        let output = pipe.fileHandleForReading
        let fd = output.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else { return nil }
        process.executableURL = executable
        process.arguments = ["web", "--no-open", "--host", "127.0.0.1", "--port", "0", "--log-level", "silent"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            stop(process, grace: shutdownTimeout)
            try? output.close()
        }
        guard let endpoint = await startupEndpoint(fd: fd, timeout: startupTimeout) else { return nil }
        let drain = Task.detached {
            var bytes = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { break }
                if count < 0 { try? await Task.sleep(for: .milliseconds(40)) }
            }
        }
        let data = await requestUsage(port: endpoint.port, token: endpoint.token, timeout: requestTimeout)
        drain.cancel()
        await drain.value
        return data
    }

    private static func stop(_ process: Process, grace: Duration) {
        if process.isRunning {
            process.terminate()
            let deadline = ContinuousClock.now.advanced(by: grace)
            while process.isRunning && ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }

    private static func startupEndpoint(fd: Int32, timeout: Duration) async -> (port: UInt16, token: String)? {
        let pattern = #"Local:\s+http://127\.0\.0\.1:([0-9]{1,5})/#token=([A-Za-z0-9_-]+)(?=\s|\x1b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while ContinuousClock.now < deadline && !Task.isCancelled {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { return nil }
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 64 * 1024 else { return nil }
                let text = String(decoding: buffer, as: UTF8.self)
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let portRange = Range(match.range(at: 1), in: text),
                   let port = UInt16(text[portRange]), port != 0,
                   let tokenRange = Range(match.range(at: 2), in: text) {
                    return (port, String(text[tokenRange]))
                }
            } else if errno != EAGAIN && errno != EINTR {
                return nil
            }
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return nil }
        }
        return nil
    }

    private static func requestUsage(port: UInt16, token: String, timeout: TimeInterval) async -> Data? {
        let url = URL(string: "http://127.0.0.1:\(port)/api/v1/oauth/usage")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            "HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
            "ProxyAutoConfigEnable": false, "ProxyAutoDiscoveryEnable": false
        ]
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 64 * 1024 else { return nil }
        return data
    }

    static func apply(_ data: Data?, status: inout ProviderStatus, now: Date = Date()) -> CodexQuota? {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = root["data"] as? [String: Any] else { return nil }
        switch payload["kind"] as? String {
        case "ok":
            status.authorization = "Signed in"
            return parse(data, now: now)
        case "error":
            let message = payload["message"] as? String ?? ""
            if payload["status"] as? Int == 401 || message.hasPrefix("No token for ") ||
                message.hasPrefix("Stored token for ") && message.contains("re-login required") {
                status.authorization = "Sign-in required"
            }
            return nil
        default:
            return nil
        }
    }

    static func parse(_ data: Data, now: Date = Date()) -> CodexQuota? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let payload = root["data"] as? [String: Any] ?? root
        guard payload["kind"] as? String != "error" else { return nil }
        var windows: [CodexQuota.LimitWindow] = []
        if let quota = payload["quota"] as? [String: Any],
           let usages = quota["usages"] as? [String: Any] {
            let periods: [(String, Int?)] = [
                ("limit5h", 300), ("limit7d", 10_080), ("monthTotal", nil), ("monthCode", nil)
            ]
            for (id, minutes) in periods {
                guard let usage = usages[id] as? [String: Any],
                      let used = number(usage["usedRatio"]), (0...1).contains(used) else { continue }
                let reset = (usage["resetAt"] as? String).flatMap { value in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: value) { return date }
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: value)
                }
                if let reset, reset <= now { continue }
                windows.append(.init(id: id, remaining: Int(((1 - used) * 100).rounded()),
                                     minutes: minutes, reset: reset))
            }
        } else if let summary = payload["summary"] as? [String: Any],
           let minutes = duration(summary["window"]),
           let window = quotaWindow(summary, id: "summary", minutes: minutes, now: now) {
            windows.append(window)
        }
        if let usage = payload["usage"] as? [String: Any],
           let window = quotaWindow(usage, id: "weekly", minutes: 10_080, now: now),
           !windows.contains(where: { $0.minutes == 10_080 }) {
            windows.append(window)
        }
        for (index, limit) in (payload["limits"] as? [[String: Any]] ?? []).enumerated() {
            guard let minutes = duration(limit["window"]),
                  let window = quotaWindow(limit["detail"] as? [String: Any] ?? limit,
                                           id: "rolling-\(index)", minutes: minutes, now: now) else { continue }
            windows.append(window)
        }
        guard let first = windows.first else { return nil }
        return CodexQuota(remaining: first.remaining, windowMinutes: first.minutes, reset: first.reset,
                          resetCredits: nil, availableResets: [], usageCreditBalance: nil,
                          unlimitedUsageCredits: false, primaryWindowID: first.id,
                          additionalWindows: Array(windows.dropFirst()))
    }

    private static func duration(_ value: Any?) -> Int? {
        guard let window = value as? [String: Any], let amount = number(window["duration"]), amount > 0,
              let unit = (window["timeUnit"] ?? window["unit"]) as? String else { return nil }
        let factor: Double
        let normalizedUnit = unit.lowercased().replacingOccurrences(of: "time_unit_", with: "")
        switch normalizedUnit.hasSuffix("s") ? String(normalizedUnit.dropLast()) : normalizedUnit {
        case "second": factor = 1 / 60
        case "minute": factor = 1
        case "hour": factor = 60
        case "day": factor = 1_440
        case "week": factor = 10_080
        default: return nil
        }
        let minutes = (amount * factor).rounded()
        guard minutes >= 1, minutes <= Double(Int32.max) else { return nil }
        return Int(minutes)
    }

    private static func quotaWindow(_ fields: [String: Any], id: String, minutes: Int,
                                    now: Date) -> CodexQuota.LimitWindow? {
        guard let limit = number(fields["limit"]), limit > 0,
              let remaining = number(fields["used"]).map({ limit - $0 }) ?? number(fields["remaining"]) else { return nil }
        let rawReset = fields["resetTime"] ?? fields["reset_at"]
        let reset: Date?
        if let timestamp = number(rawReset), timestamp > 0 {
            reset = Date(timeIntervalSince1970: timestamp >= 100_000_000_000 ? timestamp / 1_000 : timestamp)
        } else if let timestamp = rawReset as? String {
            reset = try? Date(timestamp, strategy: .iso8601)
        } else {
            reset = nil
        }
        if let reset, reset <= now { return nil }
        let fraction = min(1, max(0, remaining / limit))
        return .init(id: id, remaining: Int((fraction * 100).rounded()), minutes: minutes, reset: reset)
    }

    private static func number(_ value: Any?) -> Double? {
        if let boxed = value as? NSNumber, CFGetTypeID(boxed) == CFBooleanGetTypeID() { return nil }
        let parsed = (value as? Double) ?? (value as? String).flatMap(Double.init)
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }
}

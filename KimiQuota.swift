import CoreFoundation
import Darwin
import Foundation

enum KimiQuota {
    private final class LocalOnly: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".kimi-code/bin").path,
               home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        guard let executable = paths.filter({ $0.hasPrefix("/") })
            .map({ URL(fileURLWithPath: $0).appendingPathComponent("kimi") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }),
              let port = loopbackPort(), !Task.isCancelled else { return nil }

        let process = Process()
        let pipe = Pipe()
        let output = pipe.fileHandleForReading
        guard fcntl(output.fileDescriptor, F_SETFL, O_NONBLOCK) != -1 else { return nil }
        process.executableURL = executable
        process.arguments = ["web", "--no-open", "--host", "127.0.0.1", "--port", String(port), "--log-level", "silent"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        defer {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            try? output.close()
        }

        guard let token = await startupToken(from: output, port: port) else { return nil }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/oauth/usage")!,
                                 timeoutInterval: 5)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration, delegate: LocalOnly(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let payload = root["data"] as? [String: Any] ?? root
            if payload["kind"] as? String == "ok" {
                status.authorization = "Signed in"
            } else if let message = payload["message"] as? String,
                      message.localizedCaseInsensitiveContains("login") {
                status.authorization = "Sign-in required"
            }
        }
        return parse(data)
    }

    private static func startupToken(from output: FileHandle, port: UInt16) async -> String? {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(8)
        let pattern = "Local:\\s+http://127\\.0\\.0\\.1:\(port)/#token=([A-Za-z0-9_-]+)(?=\\s|\\u001b)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while clock.now < deadline && !Task.isCancelled {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(output.fileDescriptor, $0.baseAddress, $0.count) }
            if count == 0 { return nil }
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 64 * 1024 else { return nil }
                let text = String(decoding: buffer, as: UTF8.self)
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
            } else if errno != EAGAIN && errno != EINTR {
                return nil
            }
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return nil }
        }
        return nil
    }

    private static func loopbackPort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        return withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                guard bind(fd, socketAddress, length) == 0,
                      getsockname(fd, socketAddress, &length) == 0 else { return nil }
                return UInt16(bigEndian: pointer.pointee.sin_port)
            }
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

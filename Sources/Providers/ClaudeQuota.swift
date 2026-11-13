import CryptoKit
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

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        guard status.cliInstalled, let credentials = readCredentials(),
              let token = credentials["accessToken"] as? String, !token.isEmpty else { return nil }
        if let plan = credentials["subscriptionType"] as? String, !plan.isEmpty, plan != "unknown" {
            status.subscription = plan.capitalized
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("quota-rail/0.1", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 { status.authorization = "Credentials rejected" }
        guard (200..<300).contains(http.statusCode) else { return nil }
        status.authorization = "Signed in"
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < 65_536 else { return nil }
                data.append(byte)
            }
        } catch { return nil }
        return parse(data)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func readCredentials() -> [String: Any]? {
        let environment = ProcessInfo.processInfo.environment
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        let root = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"] ?? environment["CLAUDE_CONFIG_DIR"] ?? defaultRoot
        var service = "Claude Code-credentials"
        if !root.isEmpty, root != defaultRoot {
            let hash = SHA256.hash(data: Data(root.precomposedStringWithCanonicalMapping.utf8))
            service += "-" + hash.prefix(4).map { String(format: "%02x", $0) }.joined()
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        let user = ["LOGNAME", "USER", "LNAME", "USERNAME"].compactMap { environment[$0] }
            .first(where: { !$0.isEmpty }) ?? NSUserName()
        process.arguments = ["find-generic-password", "-s", service, "-a", user, "-w"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 65_536,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return payload["claudeAiOauth"] as? [String: Any]
    }
}

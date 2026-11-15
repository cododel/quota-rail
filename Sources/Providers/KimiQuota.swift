import CoreFoundation
import Foundation

enum KimiQuota {
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct Credential: Decodable {
        let accessToken: String
        let expiresAt: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
        }
    }

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        guard status.cliInstalled, !Task.isCancelled else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let home = environment["KIMI_CODE_HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code")
        let path = home.appendingPathComponent("credentials/kimi-code.json")
        let base = environment["KIMI_CODE_BASE_URL"] ?? "https://api.kimi.com/coding/v1"
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard ["https://api.kimi.com/coding/v1", "https://api.kimi.ai/coding/v1"].contains(normalizedBase),
              let url = URL(string: normalizedBase + "/usages") else { return nil }

        return await read(at: path, status: &status) { token in
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = 8
            let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            guard let (data, response) = try? await session.data(for: request),
                  let response = response as? HTTPURLResponse else { return nil }
            return (response.statusCode, data)
        }
    }

    static func read(at path: URL, status: inout ProviderStatus, now: Date = Date(),
                     request: (String) async -> (Int, Data)?) async -> CodexQuota? {
        let credential: Credential
        do {
            credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: path))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            status.authorization = "Sign-in required"
            return nil
        } catch {
            return nil
        }
        guard !credential.accessToken.isEmpty else {
            status.authorization = "Sign-in required"
            return nil
        }
        // Kimi owns token rotation. Read its credential file again on the next poll.
        guard credential.expiresAt > now.timeIntervalSince1970, !Task.isCancelled,
              let (code, data) = await request(credential.accessToken), code == 200 else { return nil }
        status.authorization = "Signed in"
        return parse(data, now: now)
    }

    static func parse(_ data: Data, now: Date = Date()) -> CodexQuota? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let payload = root["data"] as? [String: Any] ?? root
        guard payload["kind"] as? String != "error" else { return nil }
        var windows: [CodexQuota.LimitWindow] = []
        let directUsages = payload["usages"] as? [String: Any]
        let wrappedUsages = (payload["quota"] as? [String: Any])?["usages"] as? [String: Any]
        if let usages = directUsages ?? wrappedUsages {
            let periods: [(id: String, wireKey: String, minutes: Int?)] = [
                ("limit5h", "limit_5h", 300), ("limit7d", "limit_7d", 10_080),
                ("monthTotal", "limit_month_total", nil), ("monthCode", "limit_month_code", nil)
            ]
            let ratioKey = directUsages == nil ? "usedRatio" : "used_ratio"
            let resetKey = directUsages == nil ? "resetAt" : "reset_time"
            for (id, wireKey, minutes) in periods {
                guard let usage = usages[directUsages == nil ? id : wireKey] as? [String: Any],
                      let used = number(usage[ratioKey]), (0...1).contains(used) else { continue }
                let reset = (usage[resetKey] as? String).flatMap { value in
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

import CoreFoundation
import Darwin
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

    private struct Credential: Codable {
        let accessToken: String
        let expiresAt: Double
        let refreshToken: String?
        let expiresIn: Double?
        let scope: String?
        let tokenType: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
            case tokenType = "token_type"
        }
    }

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        guard status.cliInstalled, !Task.isCancelled else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let home = environment["KIMI_CODE_HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code")
        let base = environment["KIMI_CODE_BASE_URL"] ?? "https://api.kimi.com/coding/v1"
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let defaultAuthHost: String
        switch normalizedBase {
        case "https://api.kimi.com/coding/v1": defaultAuthHost = "https://auth.kimi.com"
        case "https://api.kimi.ai/coding/v1": defaultAuthHost = "https://auth.kimi.ai"
        default: return nil
        }
        let authHost = environment["KIMI_CODE_OAUTH_HOST"] ?? environment["KIMI_OAUTH_HOST"] ?? defaultAuthHost
        let normalizedAuth = authHost.hasSuffix("/") ? String(authHost.dropLast()) : authHost
        let quotaURL = URL(string: normalizedBase + "/usages")!
        let path = home.appendingPathComponent("credentials/kimi-code.json")
        let lock = home.appendingPathComponent("oauth/kimi-code.lock")

        return await read(at: path, lock: lock, status: &status, renew: { token in
            guard normalizedAuth == defaultAuthHost, environment["KIMI_DISABLE_OAUTH_LOCK"] != "1",
                  let url = URL(string: normalizedAuth + "/api/oauth/token"),
                  let request = refreshRequest(url: url, home: home, token: token) else { return nil }
            // Once a refresh is sent, finish reading the response even if the quota poll is cancelled.
            return await Task.detached { await send(request) }.value
        }, request: { token in
            var request = URLRequest(url: quotaURL, timeoutInterval: 8)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return await send(request)
        })
    }

    private static func send(_ request: URLRequest) async -> (Int, Data)? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse else { return nil }
        return (response.statusCode, data)
    }

    private static func refreshRequest(url: URL, home: URL, token: String) -> URLRequest? {
        guard let deviceID = try? String(contentsOf: home.appendingPathComponent("device_id"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !deviceID.isEmpty, deviceID.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        // Kimi's proper-lockfile considers the directory stale after five seconds.
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceID, forHTTPHeaderField: "X-Msh-Device-Id")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        request.setValue("QuotaRail/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue(version, forHTTPHeaderField: "X-Msh-Version")
        request.setValue("kimi_code_cli", forHTTPHeaderField: "X-Msh-Platform")
        let fields = [
            ("client_id", "17e5f671-d194-4dfb-9706-5516cb48c098"),
            ("grant_type", "refresh_token"),
            ("refresh_token", token)
        ]
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let form = fields.compactMap { key, value in
            value.addingPercentEncoding(withAllowedCharacters: unreserved).map { key + "=" + $0 }
        }
        guard form.count == fields.count else { return nil }
        request.httpBody = Data(form.joined(separator: "&").utf8)
        return request
    }

    static func read(at path: URL, lock: URL, status: inout ProviderStatus,
                     now: @escaping () -> Date = Date.init,
                     renew: (String) async -> (Int, Data)?,
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
        guard !Task.isCancelled else { return nil }
        if credential.expiresAt > now().timeIntervalSince1970 {
            guard let (code, data) = await request(credential.accessToken) else { return nil }
            if code != 401 {
                guard code == 200 else { return nil }
                status.authorization = "Signed in"
                return parse(data, now: now())
            }
        }
        guard !Task.isCancelled, let lease = RefreshLock.acquire(at: lock) else { return nil }
        let token = await refresh(at: path, lease: lease, initial: credential, now: now, renew: renew, status: &status)
        lease.release()
        guard !Task.isCancelled, let token, let (code, data) = await request(token), code == 200 else { return nil }
        status.authorization = "Signed in"
        return parse(data, now: now())
    }

    private static func refresh(at path: URL, lease: RefreshLock, initial: Credential, now: () -> Date,
                                renew: (String) async -> (Int, Data)?, status: inout ProviderStatus) async -> String? {
        guard let previous = try? Data(contentsOf: path),
              let current = try? JSONDecoder().decode(Credential.self, from: previous) else { return nil }
        if current.accessToken != initial.accessToken || current.refreshToken != initial.refreshToken ||
            current.expiresAt != initial.expiresAt {
            // Another process renewed or changed the sign-in while the quota request was in flight.
            return current.expiresAt > now().timeIntervalSince1970 && !current.accessToken.isEmpty
                ? current.accessToken : nil
        }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            status.authorization = "Sign-in required"
            return nil
        }
        guard !Task.isCancelled, lease.isCurrent else { return nil }

        // Reserve a private file before the exchange can invalidate the old refresh token.
        var template = Array((path.path + ".tmp.quota-rail.XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { return nil }
        let temporary = String(cString: template)
        defer { _ = unlink(temporary) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

        guard let (code, data) = await renew(refreshToken),
              lease.isCurrent, (try? Data(contentsOf: path)) == previous else { return nil }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if code == 401 || code == 403 || body?["error"] as? String == "invalid_grant" {
            status.authorization = "Sign-in required"
            return nil
        }
        guard code == 200, let body, let access = body["access_token"] as? String, !access.isEmpty,
              let rotation = body["refresh_token"] as? String, !rotation.isEmpty,
              let lifetime = number(body["expires_in"]), lifetime > 0 else { return nil }
        let saved = Credential(accessToken: access, expiresAt: floor(now().timeIntervalSince1970) + lifetime,
                               refreshToken: rotation, expiresIn: lifetime,
                               scope: body["scope"] as? String ?? current.scope ?? "",
                               tokenType: body["token_type"] as? String ?? "Bearer")
        do {
            try file.write(contentsOf: JSONEncoder().encode(saved))
            try file.synchronize()
            try file.close()
        } catch {
            return nil
        }
        guard lease.isCurrent, (try? Data(contentsOf: path)) == previous,
              rename(temporary, path.path) == 0 else { return nil }
        return access
    }

    private struct RefreshLock {
        private static let staleSeconds: TimeInterval = 5
        let url: URL
        let descriptor: Int32

        static func acquire(at url: URL) -> Self? {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            if mkdir(url.path, 0o700) != 0 {
                guard errno == EEXIST, let first = directoryInfo(at: url), isStale(first),
                      let last = directoryInfo(at: url), sameDirectory(first, last), isStale(last),
                      rmdir(url.path) == 0, mkdir(url.path, 0o700) == 0 else { return nil }
            }
            let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { return nil }
            return Self(url: url, descriptor: fd)
        }

        var isCurrent: Bool {
            guard let info = ownedDirectory else { return false }
            return !Self.isStale(info)
        }

        func release() {
            if ownedDirectory != nil { _ = rmdir(url.path) }
            close(descriptor)
        }

        private var ownedDirectory: stat? {
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, let visible = Self.directoryInfo(at: url),
                  Self.sameDirectory(opened, visible) else { return nil }
            return visible
        }

        private static func directoryInfo(at url: URL) -> stat? {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
            return info
        }

        private static func sameDirectory(_ lhs: stat, _ rhs: stat) -> Bool {
            lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
        }

        private static func isStale(_ info: stat) -> Bool {
            let modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            return Date().timeIntervalSince1970 - modified > staleSeconds
        }
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

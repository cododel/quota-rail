import Darwin
import Foundation

enum GrokQuota {
    private struct Credential: Decodable {
        var isExpired: Bool { expiration != 0 && expiration <= Date().timeIntervalSince1970 }

        let auth_mode: String?
        let key: String?
        let expiration: Double

        private enum CodingKeys: String, CodingKey {
            case auth_mode, key, expires_at
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            auth_mode = try fields.decodeIfPresent(String.self, forKey: .auth_mode)
            key = try fields.decodeIfPresent(String.self, forKey: .key)
            if let timestamp = try? fields.decode(Double.self, forKey: .expires_at) {
                expiration = timestamp
            } else if let value = try? fields.decode(String.self, forKey: .expires_at) {
                expiration = Double(value) ?? GrokQuota.parseDate(value)?.timeIntervalSince1970 ?? 0
            } else {
                expiration = 0
            }
        }
    }

    private struct Billing: Decodable {
        let isUnifiedBillingUser: Bool?
        let creditUsagePercent: Double
        let currentPeriod: Period

        struct Period: Decodable {
            let type: String
            let end: String
        }
    }

    private struct Envelope: Decodable {
        let config: Billing
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func read(status: inout ProviderStatus, previouslyRejected: Bool = false) async -> CodexQuota? {
        if previouslyRejected { status.authorization = "Credentials rejected" }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = ProcessInfo.processInfo.environment["GROK_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".grok", isDirectory: true)
        return await read(at: directory.appendingPathComponent("auth.json"), status: &status,
                          refresh: { await sessionRefresh.run() }, request: requestBilling)
    }

    static func read(at path: URL, status: inout ProviderStatus,
                     refresh: () async -> Void,
                     request: (String) async -> (Int, Data)?) async -> CodexQuota? {
        guard let credential = readCredential(at: path, status: &status),
              let token = credential.key else { return nil }

        if !credential.isExpired {
            guard let initial = await request(token) else { return nil }
            if initial.0 != 401 { return apply(initial, status: &status) }
            status.authorization = "Credentials rejected"
        }
        guard !Task.isCancelled else { return nil }
        await refresh()
        guard !Task.isCancelled,
              let renewed = readCredential(at: path, status: &status),
              !renewed.isExpired, let renewedToken = renewed.key else { return nil }
        return apply(await request(renewedToken), status: &status)
    }

    private static func requestBilling(_ token: String) async -> (Int, Data)? {
        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (payload, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, payload)
    }

    private static func apply(_ response: (Int, Data)?, status: inout ProviderStatus) -> CodexQuota? {
        guard let (code, payload) = response else { return nil }
        if code == 401 {
            status.authorization = "Credentials rejected"
        }
        guard code == 200 else { return nil }
        status.authorization = "Signed in"
        if let billing = decodeBilling(payload),
           billing.isUnifiedBillingUser == true,
           billing.currentPeriod.type == "USAGE_PERIOD_TYPE_WEEKLY" {
            status.subscription = "Shared weekly access"
        }
        return parse(payload)
    }

    static func readAccessToken(at path: URL, status: inout ProviderStatus) -> String? {
        readCredential(at: path, status: &status)?.key
    }

    private static func readCredential(at path: URL, status: inout ProviderStatus) -> Credential? {
        do {
            let data = try Data(contentsOf: path)
            let credentials = try JSONDecoder().decode([String: Credential].self, from: data)
            let token = selectCredential(from: credentials)
            if token == nil && status.authorization != "Credentials rejected" { status.authorization = "Sign-in required" }
            return token
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            if status.authorization != "Credentials rejected" { status.authorization = "Sign-in required" }
            return nil
        } catch {
            return nil
        }
    }

    static func accessToken(from data: Data) -> String? {
        guard let credentials = try? JSONDecoder().decode([String: Credential].self, from: data) else { return nil }
        return selectCredential(from: credentials)?.key
    }

    private static func selectCredential(from credentials: [String: Credential]) -> Credential? {
        return credentials.values
            .filter { $0.auth_mode == "oidc" && $0.key?.isEmpty == false }
            .max { $0.expiration < $1.expiration }
    }

    private static let sessionRefresh = SessionRefresh()

    actor SessionRefresh {
        private let clock = ContinuousClock()
        private let waitLimit: Duration
        private let lifetimeLimit: Duration
        private let pollInterval: Duration
        private let arguments: [String]
        private let executable: @Sendable () -> String?
        private var process: Process?
        private var waitDeadline: ContinuousClock.Instant?
        private var retryAfter: ContinuousClock.Instant?

        init(waitLimit: Duration = .seconds(60), lifetimeLimit: Duration = .seconds(180),
             pollInterval: Duration = .milliseconds(200), arguments: [String] = ["models"],
             executable: @escaping @Sendable () -> String? = { ProviderStatus.executablePath("grok") }) {
            self.waitLimit = waitLimit
            self.lifetimeLimit = lifetimeLimit
            self.pollInterval = pollInterval
            self.arguments = arguments
            self.executable = executable
        }

        var isRunning: Bool { process?.isRunning == true }

        func run() async {
            if !isRunning {
                process = nil
                guard !Task.isCancelled, retryAfter.map({ clock.now >= $0 }) ?? true,
                      let executable = executable() else { return }
                let child = Process()
                child.executableURL = URL(fileURLWithPath: executable)
                child.arguments = arguments
                child.currentDirectoryURL = FileManager.default.temporaryDirectory
                child.standardInput = FileHandle.nullDevice
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                retryAfter = clock.now.advanced(by: .seconds(120))
                do { try child.run() } catch { return }
                process = child
                waitDeadline = clock.now.advanced(by: waitLimit)
                let killDeadline = clock.now.advanced(by: lifetimeLimit)
                Task { await supervise(child, until: killDeadline) }
            }
            guard let child = process, let deadline = waitDeadline else { return }
            while child.isRunning && clock.now < deadline {
                do { try await clock.sleep(until: min(deadline, clock.now.advanced(by: pollInterval))) }
                catch { return }
            }
        }

        private func supervise(_ child: Process, until deadline: ContinuousClock.Instant) async {
            // Keep supervision alive after the quota caller stops waiting or is cancelled.
            while child.isRunning && clock.now < deadline {
                try? await clock.sleep(until: min(deadline, clock.now.advanced(by: pollInterval)))
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // Foundation reaps the child. Keep it registered until it has actually exited.
            while child.isRunning { try? await Task.sleep(for: pollInterval) }
            if process === child { process = nil }
        }
    }

    private static func decodeBilling(_ data: Data) -> Billing? {
        let decoder = JSONDecoder()
        return (try? decoder.decode(Envelope.self, from: data))?.config
            ?? (try? decoder.decode(Billing.self, from: data))
    }

    static func parse(_ data: Data, now: Date = Date()) -> CodexQuota? {
        guard let billing = decodeBilling(data), billing.isUnifiedBillingUser != false,
              billing.currentPeriod.type == "USAGE_PERIOD_TYPE_WEEKLY",
              (0...100).contains(billing.creditUsagePercent) else { return nil }

        guard let reset = parseDate(billing.currentPeriod.end), reset > now else { return nil }
        return CodexQuota(remaining: Int((100 - billing.creditUsagePercent).rounded()),
                          windowMinutes: 10_080, reset: reset, resetCredits: nil,
                          availableResets: [], usageCreditBalance: nil, unlimitedUsageCredits: false)
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions.insert(.withFractionalSeconds)
        return iso8601.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

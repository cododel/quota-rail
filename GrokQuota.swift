import Foundation

enum GrokQuota {
    private struct Credential: Decodable {
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

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = ProcessInfo.processInfo.environment["GROK_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".grok", isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("auth.json")),
              let token = accessToken(from: data) else { return nil }

        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (payload, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 {
            status.authorization = "Credentials rejected"
        }
        guard http.statusCode == 200 else { return nil }
        status.authorization = "Signed in"
        if let billing = decodeBilling(payload),
           billing.isUnifiedBillingUser == true,
           billing.currentPeriod.type == "USAGE_PERIOD_TYPE_WEEKLY" {
            status.subscription = "Shared weekly access"
        }
        return parse(payload)
    }

    static func accessToken(from data: Data) -> String? {
        guard let credentials = try? JSONDecoder().decode([String: Credential].self, from: data) else { return nil }
        return credentials.values
            .filter { $0.auth_mode == "oidc" && $0.key?.isEmpty == false }
            .max { $0.expiration < $1.expiration }?.key
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

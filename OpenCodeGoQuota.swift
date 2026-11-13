import CoreFoundation
import Foundation

enum OpenCodeGoQuota {
    private struct Credential: Decodable {
        let key: String?
    }

    static func read(status: inout ProviderStatus) async -> CodexQuota? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let roots = [dataHome, home.appendingPathComponent("Library/Application Support").path,
                     home.appendingPathComponent(".local/share").path]
        let key = roots.compactMap { root -> String? in
            guard let root, root.hasPrefix("/") else { return nil }
            let path = URL(fileURLWithPath: root).appendingPathComponent("opencode/auth.json")
            guard let data = try? Data(contentsOf: path),
                  let entries = try? JSONDecoder().decode([String: Credential].self, from: data),
                  let key = entries["opencode-go"]?.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else { return nil }
            return key
        }.first
        guard let key else { return nil }
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!, timeoutInterval: 8)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 {
            status.authorization = "Credentials rejected"
        }
        guard http.statusCode == 200 else { return nil }
        status.authorization = "Signed in"
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           root["usage"] is [String: Any] {
            status.subscription = "Go access confirmed"
        }
        return parse(data)
    }

    static func parse(_ data: Data, now: Date = Date()) -> CodexQuota? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else { return nil }
        let periods: [(String, Int?)] = [("rolling", 300), ("weekly", 10_080), ("monthly", nil)]
        let windows = periods.compactMap { id, minutes -> CodexQuota.LimitWindow? in
            guard let period = usage[id] as? [String: Any],
                  let used = number(period["percent"]), (0...100).contains(used) else { return nil }
            let reset: Date?
            if let timestamp = number(period["resetsAt"]), timestamp > 0 {
                reset = Date(timeIntervalSince1970: timestamp >= 100_000_000_000 ? timestamp / 1_000 : timestamp)
            } else if let value = period["resetsAt"] as? String {
                reset = try? Date(value, strategy: .iso8601)
            } else {
                reset = nil
            }
            if let reset, reset <= now { return nil }
            return .init(id: id, remaining: Int((100 - used).rounded()), minutes: minutes, reset: reset)
        }
        guard let primary = windows.first else { return nil }
        return CodexQuota(remaining: primary.remaining, windowMinutes: primary.minutes, reset: primary.reset,
                          resetCredits: nil, availableResets: [], usageCreditBalance: nil,
                          unlimitedUsageCredits: false, primaryWindowID: primary.id,
                          additionalWindows: Array(windows.dropFirst()))
    }

    private static func number(_ value: Any?) -> Double? {
        if let boxed = value as? NSNumber, CFGetTypeID(boxed) == CFBooleanGetTypeID() { return nil }
        let number = (value as? Double) ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite else { return nil }
        return number
    }
}

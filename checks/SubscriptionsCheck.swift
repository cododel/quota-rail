import Foundation

@main
struct SubscriptionsCheck {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = CodexQuota(remaining: 37, windowMinutes: 10_080, reset: now,
            resetCredits: 3, availableResets: [], usageCreditBalance: 125,
            unlimitedUsageCredits: false)
        let normal = OverlaySubscription.resolve(codex: live, includeMocks: false, now: now)
        precondition(normal.count == 1 && !normal[0].isMock && normal[0].quota.remaining == 37)
        precondition(OverlaySubscription.resolve(codex: nil, includeMocks: false, now: now).isEmpty)
        let mixed = OverlaySubscription.resolve(codex: live, includeMocks: true, now: now)
        precondition(mixed.map(\.id) == ["claude", "codex", "gemini"])
        precondition(mixed.filter(\.isMock).count == 2)
        precondition(mixed[1].quota.remaining == 37 && mixed[1].quota.usageCreditBalance == 125)
        let mocks = OverlaySubscription.resolve(codex: nil, includeMocks: true, now: now)
        precondition(mocks.count == 3 && mocks.allSatisfy(\.isMock))
        precondition(Set(mocks.map(\.id)).count == 3)
        let windows = CodexQuota.readWindows([
            "primary": ["usedPercent": 27.0, "windowDurationMins": 300, "resetsAt": now.timeIntervalSince1970 + 3600] as [String: Any],
            "secondary": ["usedPercent": 58.0, "windowDurationMins": 10080, "resetsAt": now.timeIntervalSince1970 + 86400] as [String: Any]
        ], now: now)
        precondition(windows.map(\.label) == ["5h", "7d"])
        precondition(windows.map(\.remaining) == [73, 42])
        precondition(mocks[0].quota.windows.map(\.label) == ["5h", "7d"])
        precondition(mocks[2].quota.windows.map(\.label) == ["5h", "7d"])
        precondition(mocks[2].name == "Antigravity")
        precondition(mocks[2].limitGroups.map(\.name) == ["Gemini", "Claude/GPT"])
        precondition(mocks[2].limitGroups.allSatisfy { $0.windows.map(\.label) == ["5h", "7d"] })
        precondition(mocks[0].limitGroups.isEmpty && mocks[1].limitGroups.isEmpty)
        precondition(mocks[2].quota.resetCredits == nil)
        precondition(mocks[2].quota.availableResets.isEmpty)
        precondition(mocks[2].quota.usageCreditBalance == nil)
        precondition(mocks[0].quota.resetCredits == 1)
        precondition(CodexQuota.readWindows(["primary": ["usedPercent": 101.0]], now: now).isEmpty)
        let payload: [String: Any] = [
            "gemini-5h": ["remaining_fraction": 0.52, "reset_time": now.addingTimeInterval(3600).ISO8601Format()],
            "gemini-weekly": ["remaining_fraction": 0.68, "reset_time": now.addingTimeInterval(86400).ISO8601Format()],
            "3p-5h": ["remaining_fraction": 0.81, "reset_time": now.addingTimeInterval(7200).ISO8601Format()],
            "3p-weekly": ["remaining_fraction": 0.64, "reset_time": now.addingTimeInterval(172800).ISO8601Format()]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let agy = AntigravityQuota.parse(data, now: now)!
        precondition(agy.gemini.windows.map(\.remaining) == [52, 68])
        precondition(agy.thirdParty.windows.map(\.remaining) == [81, 64])
        precondition(AntigravityQuota.parse(data, now: now.addingTimeInterval(400000)) == nil)
        var partial = payload
        partial.removeValue(forKey: "3p-weekly")
        precondition(AntigravityQuota.parse(try! JSONSerialization.data(withJSONObject: partial), now: now) == nil)
        var invalid = payload
        invalid["gemini-5h"] = ["remaining_fraction": 1.2, "reset_time": now.addingTimeInterval(3600).ISO8601Format()]
        precondition(AntigravityQuota.parse(try! JSONSerialization.data(withJSONObject: invalid), now: now) == nil)
        let automatic = OverlaySubscription.resolve(codex: live, antigravity: agy, now: now)
        precondition(automatic.map(\.isMock) == [true, false, false])
        precondition(automatic[2].limitGroups[1].windows.map(\.remaining) == [81, 64])
        let forced = OverlaySubscription.resolve(codex: live, antigravity: agy, fullDemo: true, now: now)
        precondition(forced.allSatisfy(\.isMock))
        let fallback = OverlaySubscription.resolve(codex: live, antigravity: nil, now: now)
        precondition(fallback.map(\.isMock) == [true, false, true])
        let claudePayload: [String: Any] = [
            "five_hour": ["utilization": 25.0, "resets_at": now.addingTimeInterval(3600).ISO8601Format()],
            "seven_day": ["utilization": 60.0, "resets_at": now.addingTimeInterval(86400).ISO8601Format()]
        ]
        let claudeLive = ClaudeQuota.parse(try! JSONSerialization.data(withJSONObject: claudePayload), now: now)!
        precondition(claudeLive.windows.map(\.remaining) == [75, 40])
        precondition(claudeLive.resetCredits == nil && claudeLive.usageCreditBalance == nil)
        let allLive = OverlaySubscription.resolve(codex: live, antigravity: agy, claude: claudeLive, now: now)
        precondition(allLive.allSatisfy { !$0.isMock })
        precondition(OverlaySubscription.resolve(codex: live, antigravity: agy, claude: claudeLive,
            fullDemo: true, now: now).allSatisfy(\.isMock))
        let grokCredentials = Data("""
            {"older":{"auth_mode":"oidc","key":"older","expires_at":1700000000},
             "current":{"auth_mode":"oidc","key":"current","expires_at":"2027-01-20T14:15:30Z"}}
            """.utf8)
        precondition(GrokQuota.accessToken(from: grokCredentials) == "current")
        let grokPayload = Data("""
            {"config":{"isUnifiedBillingUser":true,"creditUsagePercent":41,
            "currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2027-01-20T14:15:30.192Z"}}}
            """.utf8)
        let grok = GrokQuota.parse(grokPayload, now: now)!
        precondition(grok.remaining == 59 && grok.windows.map(\.label) == ["7d"])
        precondition(GrokQuota.parse(grokPayload, now: now.addingTimeInterval(604_800)) == nil)
        let withGrok = OverlaySubscription.resolve(codex: live, antigravity: agy, claude: claudeLive, grok: grok, now: now)
        precondition(withGrok.map(\.id) == ["claude", "codex", "gemini", "grok"])
        print("PASS: Antigravity parsing, invalid/expired data, per-provider fallback, forced demo")
        print("PASS: both quota windows, percentages, Claude mock and single banked reset")
        print("PASS: flag off, live quota preservation, two-mock fill, three-mock fallback")
    }
}

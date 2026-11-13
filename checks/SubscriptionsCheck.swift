import Foundation
import SwiftUI

@main
struct SubscriptionsCheck {
    static func main() {
        func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
            Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: 1)
        }
        let paletteCases: [(Int, Color)] = [
            (0, rgb(239, 92, 97)), (3, rgb(239, 92, 97)),
            (5, rgb(240.5, 116, 83)), (7, rgb(242, 140, 69)),
            (12, rgb(242, 140, 69)), (18, rgb(242, 140, 69)),
            (20, rgb(237, 169, 79.5)), (22, rgb(232, 198, 90)),
            (38, rgb(232, 198, 90)), (48, rgb(232, 198, 90)),
            (49, rgb(219.5, 200.1875, 96.875)),
            (50, rgb(192, 205, 112)),
            (51, rgb(164.5, 209.8125, 127.125)),
            (52, rgb(152, 212, 134)), (73, rgb(152, 212, 134)),
            (100, rgb(152, 212, 134))
        ]
        for (remaining, expected) in paletteCases {
            precondition(QuotaPalette.color(remaining: remaining) == expected,
                         "Incorrect quota color at \(remaining)%")
        }
        precondition(QuotaPalette.color(remaining: -1) == QuotaPalette.color(remaining: 0))
        precondition(QuotaPalette.color(remaining: 101) == QuotaPalette.color(remaining: 100))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = CodexQuota(remaining: 37, windowMinutes: 10_080, reset: now,
            resetCredits: 3, availableResets: [], usageCreditBalance: 125,
            unlimitedUsageCredits: false)
        let normal = OverlaySubscription.resolve(codex: live, now: now)
        precondition(normal.count == 1 && !normal[0].isMock && normal[0].quota.remaining == 37)
        let sameQuota = OverlaySubscription.resolve(codex: live, claude: live, grok: live,
                                                    openCodeGo: live, kimi: live, now: now)
        precondition(sameQuota.allSatisfy { $0.color == rgb(232, 198, 90) })
        precondition(OverlaySubscription.resolve(codex: nil, now: now).isEmpty)
        precondition(normal[0].quota.usageCreditBalance == 125)
        let mocks = OverlaySubscription.resolve(codex: nil, fullDemo: true, now: now)
        precondition(mocks.allSatisfy(\.isMock))
        precondition(mocks.allSatisfy { $0.color == QuotaPalette.color(remaining: $0.quota.remaining) })
        precondition(mocks.map(\.id) == ["claude", "codex", "gemini", "grok", "opencode-go", "kimi"])
        precondition(mocks.dropFirst(3).map { $0.quota.windows.map(\.label) } ==
            [["7d"], ["5h", "7d", "Monthly"], ["5h", "7d"]])
        precondition(mocks.dropFirst(3).allSatisfy { $0.quota.resetCredits == nil && $0.quota.usageCreditBalance == nil })
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
        precondition(automatic.map(\.id) == ["codex", "gemini"] && automatic.allSatisfy { !$0.isMock })
        precondition(automatic[1].limitGroups[1].windows.map(\.remaining) == [81, 64])
        let forced = OverlaySubscription.resolve(codex: live, antigravity: agy, fullDemo: true, now: now)
        precondition(forced.allSatisfy(\.isMock))
        let claudePayload: [String: Any] = [
            "five_hour": ["utilization": 25.0, "resets_at": now.addingTimeInterval(3600).ISO8601Format()],
            "seven_day": ["utilization": 60.0, "resets_at": now.addingTimeInterval(86400).ISO8601Format()]
        ]
        let claudeLive = ClaudeQuota.parse(try! JSONSerialization.data(withJSONObject: claudePayload), now: now)!
        precondition(claudeLive.windows.map(\.remaining) == [75, 40])
        precondition(claudeLive.resetCredits == nil && claudeLive.usageCreditBalance == nil)
        let allLive = OverlaySubscription.resolve(codex: live, antigravity: agy, claude: claudeLive, now: now)
        precondition(allLive.map(\.id) == ["claude", "codex", "gemini"] && allLive.allSatisfy { !$0.isMock })
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
        let goPayload = Data("""
            {"usage":{"rolling":{"percent":25,"resetsAt":1800003600000},
            "weekly":{"percent":"60","resetsAt":1800086400},"monthly":{"percent":90}}}
            """.utf8)
        let go = OpenCodeGoQuota.parse(goPayload, now: now)!
        precondition(go.windows.map(\.label) == ["5h", "7d", "Monthly"])
        precondition(go.windows.map(\.remaining) == [75, 40, 10])
        precondition(go.windows[0].reset == now.addingTimeInterval(3_600))
        let monthlyOnly = OpenCodeGoQuota.parse(goPayload, now: now.addingTimeInterval(86_400))
        precondition(monthlyOnly?.windows.map(\.label) == ["Monthly"])
        let withGo = OverlaySubscription.resolve(codex: live, openCodeGo: go, now: now)
        precondition(withGo.map(\.id) == ["codex", "opencode-go"])
        let kimiPayload = Data("""
            {"data":{"usage":{"limit":"100","used":30,"resetTime":1800086400},
            "limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},
            "detail":{"limit":100,"remaining":80,"resetTime":1800003600000}}]}}
            """.utf8)
        let kimi = KimiQuota.parse(kimiPayload, now: now)!
        precondition(kimi.windows.map(\.label) == ["7d", "5h"])
        precondition(kimi.windows.map(\.remaining) == [70, 80])
        precondition(kimi.windows.last?.reset == now.addingTimeInterval(3_600))
        let kimiModern = Data("""
            {"data":{"kind":"ok","quota":{"usages":{
              "limit5h":{"usedRatio":0,"resetAt":"2027-01-20T14:15:30.192Z"},
              "limit7d":{"usedRatio":0.25},"monthTotal":{"usedRatio":0.5},"monthCode":{"usedRatio":1}
            },"extraUsage":null}}}
            """.utf8)
        let modernWindows = KimiQuota.parse(kimiModern, now: now)?.windows
        precondition(modernWindows?.map(\.label) == ["5h", "7d", "Monthly", "Monthly code"])
        precondition(modernWindows?.map(\.remaining) == [100, 75, 50, 0])
        precondition(modernWindows?.first?.reset != nil)
        let kimiEmpty = Data(#"{"data":{"kind":"ok","quota":{"usages":{},"extraUsage":null}}}"#.utf8)
        precondition(KimiQuota.parse(kimiEmpty, now: now) == nil)
        let kimiSummary = Data("""
            {"summary":{"window":{"duration":7,"unit":"day"},"limit":100,"used":42}}
            """.utf8)
        precondition(KimiQuota.parse(kimiSummary, now: now)?.remaining == 58)
        precondition(KimiQuota.parse(Data(#"{"data":{"kind":"error"}}"#.utf8), now: now) == nil)
        precondition(OverlaySubscription.resolve(codex: nil, kimi: kimi, now: now).map(\.id) == ["kimi"])
        print("PASS: Antigravity parsing, invalid/expired data, live-only subscriptions, forced demo")
        print("PASS: both quota windows, percentages, Claude mock and single banked reset")
        print("PASS: empty state without live quotas, demo fixtures only in full demo")
        print("PASS: quota palette zones, soft boundaries, endpoints and provider-independent colors")
    }
}

import SwiftUI

struct OverlaySubscription: Identifiable {
    let id: String
    let name: String
    let color: Color
    let quota: CodexQuota
    let isMock: Bool
    var limitGroups: [LimitGroup] = []

    struct LimitGroup: Identifiable {
        let id: String
        let name: String
        let windows: [CodexQuota.LimitWindow]
    }

    static func resolve(codex: CodexQuota?, antigravity: AntigravityQuota? = nil, claude: CodexQuota? = nil, grok: CodexQuota? = nil, includeMocks: Bool = true, fullDemo: Bool = false, now: Date) -> [Self] {
        var live: [String: Self] = [:]
        if !fullDemo {
            if let claude {
                live["claude"] = Self(id: "claude", name: "Claude", color: .orange, quota: claude, isMock: false)
            }
            if let codex {
                live["codex"] = Self(id: "codex", name: "Codex", color: .mint, quota: codex, isMock: false)
            }
            if let antigravity {
                live["gemini"] = Self(id: "gemini", name: "Antigravity", color: .yellow,
                    quota: antigravity.gemini, isMock: false, limitGroups: [
                        LimitGroup(id: "gemini", name: "Gemini", windows: antigravity.gemini.windows),
                        LimitGroup(id: "claude-gpt", name: "Claude/GPT", windows: antigravity.thirdParty.windows)
                    ])
            }
        }
        let grokSubscription = fullDemo ? nil : grok.map {
            Self(id: "grok", name: "Grok Build", color: .cyan, quota: $0, isMock: false)
        }
        if !includeMocks && !fullDemo {
            return ["claude", "codex", "gemini"].compactMap { live[$0] } + [grokSubscription].compactMap { $0 }
        }
        let examples: [(String, String, Color, Int, Int, Int, [Int])] = [
            ("claude", "Claude", .orange, 73, 300, 2_450, [2]),
            ("codex", "Codex", .mint, 21, 10_080, 12_800, [4, 11, 21]),
            ("gemini", "Antigravity", .yellow, 52, 300, 0, []),
        ]
        let subscriptions = examples.map { id, name, color, remaining, window, balance, expirationDays in
            if let real = live[id] { return real }
            // UI fixtures only; these fields do not imply provider API capabilities or pricing.
            let resets = expirationDays.enumerated().map { index, days in
                CodexQuota.ResetCredit(
                    id: "mock-\(id)-\(index)",
                    expiresAt: now.addingTimeInterval(TimeInterval(days * 86_400 + index * 3_600))
                )
            }
            let quota = CodexQuota(
                remaining: remaining, windowMinutes: window,
                reset: now.addingTimeInterval(TimeInterval(window * 30)),
                resetCredits: id == "gemini" ? nil : resets.count,
                availableResets: resets,
                usageCreditBalance: id == "gemini" ? nil : Decimal(balance),
                unlimitedUsageCredits: false,
                additionalWindows: [CodexQuota.LimitWindow(
                    id: "secondary", remaining: id == "claude" ? 42 : 68,
                    minutes: window == 300 ? 10_080 : 300,
                    reset: now.addingTimeInterval(window == 300 ? 345_600 : 7_200)
                )]
            )
            // Keep the existing ID so saved visibility preferences survive the rename.
            let groups: [LimitGroup] = id == "gemini" ? [
                LimitGroup(id: "gemini", name: "Gemini", windows: quota.windows),
                LimitGroup(id: "claude-gpt", name: "Claude/GPT", windows: [
                    CodexQuota.LimitWindow(id: "five-hour", remaining: 81, minutes: 300,
                        reset: now.addingTimeInterval(10_800)),
                    CodexQuota.LimitWindow(id: "weekly", remaining: 64, minutes: 10_080,
                        reset: now.addingTimeInterval(410_400))
                ])
            ] : []
            return Self(id: id, name: name, color: color, quota: quota, isMock: true, limitGroups: groups)
        }
        return subscriptions + [grokSubscription].compactMap { $0 }
    }
}

import SwiftUI

struct OverlaySubscription: Identifiable {
    let id: String
    let name: String
    var color: Color { QuotaPalette.color(remaining: quota.remaining) }
    let quota: CodexQuota
    let isMock: Bool
    var limitGroups: [LimitGroup] = []

    struct LimitGroup: Identifiable {
        let id: String
        let name: String
        let windows: [CodexQuota.LimitWindow]
    }

    static func resolve(codex: CodexQuota?, antigravity: AntigravityQuota? = nil, claude: CodexQuota? = nil, grok: CodexQuota? = nil, openCodeGo: CodexQuota? = nil, kimi: CodexQuota? = nil, fullDemo: Bool = false, now: Date) -> [Self] {
        if !fullDemo {
            var live: [Self] = []
            if let claude {
                live.append(Self(id: "claude", name: "Claude", quota: claude, isMock: false))
            }
            if let codex {
                live.append(Self(id: "codex", name: "Codex", quota: codex, isMock: false))
            }
            if let antigravity {
                live.append(Self(id: "gemini", name: "Antigravity",
                    quota: antigravity.gemini, isMock: false, limitGroups: [
                        LimitGroup(id: "gemini", name: "Gemini", windows: antigravity.gemini.windows),
                        LimitGroup(id: "claude-gpt", name: "Claude/GPT", windows: antigravity.thirdParty.windows)
                    ]))
            }
            if let grok {
                live.append(Self(id: "grok", name: "Grok Build", quota: grok, isMock: false))
            }
            if let openCodeGo {
                live.append(Self(id: "opencode-go", name: "OpenCode Go", quota: openCodeGo, isMock: false))
            }
            if let kimi {
                live.append(Self(id: "kimi", name: "Kimi", quota: kimi, isMock: false))
            }
            return live
        }
        let examples: [(String, String, Int, Int, Int, [Int])] = [
            ("claude", "Claude", 73, 300, 2_450, [2]),
            ("codex", "Codex", 21, 10_080, 12_800, [4, 11, 21]),
            ("gemini", "Antigravity", 52, 300, 0, []),
        ]
        let demo = examples.map { id, name, remaining, window, balance, expirationDays in
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
            return Self(id: id, name: name, quota: quota, isMock: true, limitGroups: groups)
        }
        let additional: [(id: String, name: String, windows: [CodexQuota.LimitWindow])] = [
            ("grok", "Grok Build", [
                .init(id: "weekly", remaining: 57, minutes: 10_080, reset: now.addingTimeInterval(259_200))
            ]),
            ("opencode-go", "OpenCode Go", [
                .init(id: "rolling", remaining: 76, minutes: 300, reset: now.addingTimeInterval(7_200)),
                .init(id: "weekly", remaining: 48, minutes: 10_080, reset: now.addingTimeInterval(432_000)),
                .init(id: "monthly", remaining: 62, minutes: nil, reset: now.addingTimeInterval(1_209_600))
            ]),
            ("kimi", "Kimi", [
                .init(id: "limit5h", remaining: 84, minutes: 300, reset: now.addingTimeInterval(10_800)),
                .init(id: "limit7d", remaining: 65, minutes: 10_080, reset: now.addingTimeInterval(345_600))
            ])
        ]
        return demo + additional.compactMap { provider in
            guard let primary = provider.windows.first else { return nil }
            let quota = CodexQuota(
                remaining: primary.remaining, windowMinutes: primary.minutes, reset: primary.reset,
                resetCredits: nil, availableResets: [], usageCreditBalance: nil, unlimitedUsageCredits: false,
                primaryWindowID: primary.id, additionalWindows: Array(provider.windows.dropFirst())
            )
            return Self(id: provider.id, name: provider.name, quota: quota, isMock: true)
        }
    }
}

extension OverlaySubscription {
    static func moving(_ id: String, to index: Int, in order: [String]) -> [String] {
        guard order.indices.contains(index), let source = order.firstIndex(of: id) else { return order }
        var updated = order
        updated.remove(at: source)
        updated.insert(id, at: index)
        return updated
    }

    static func replacingVisibleOrder(_ order: [String], with visible: [String]) -> [String] {
        let visibleIDs = Set(visible)
        var replacements = visible.makeIterator()
        let complete = order + visible.filter { !order.contains($0) }
        return complete.map { id in
            visibleIDs.contains(id) ? replacements.next() ?? id : id
        }
    }
}

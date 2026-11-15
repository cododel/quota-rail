import Foundation
import SwiftUI

@main
struct SubscriptionsCheck {
    @MainActor
    private static func checkQuotaPolling() async {
        let clock = ContinuousClock()
        let interval = Duration.milliseconds(100)
        var starts: [ContinuousClock.Instant] = []
        var firstRefresh: CheckedContinuation<Void, Never>?
        let polling = QuotaPolling(interval: interval) {
            starts.append(clock.now)
            if starts.count == 1 {
                await withCheckedContinuation { firstRefresh = $0 }
            }
        }
        defer { polling.stop() }

        func waitForStarts(_ count: Int) async {
            let deadline = clock.now.advanced(by: .seconds(2))
            while starts.count < count && clock.now < deadline {
                try! await Task.sleep(for: .milliseconds(5))
            }
            precondition(starts.count == count)
        }

        try! await Task.sleep(for: interval)
        precondition(starts.isEmpty, "The rail starts hidden")
        polling.setActive(true)
        await waitForStarts(1)
        polling.setActive(false)
        polling.setActive(true)
        polling.setActive(false)
        let completed = clock.now
        firstRefresh?.resume()
        try! await Task.sleep(for: interval + interval)
        precondition(starts.count == 1, "A hidden rail does not poll after a refresh finishes")

        polling.setActive(true)
        await waitForStarts(2)
        precondition(starts[1] >= completed.advanced(by: interval))
        polling.setActive(false)
        polling.setActive(true)
        await waitForStarts(3)
        precondition(starts[2] >= starts[1].advanced(by: interval), "Reopening keeps the cooldown")
        await waitForStarts(4)
        precondition(starts[3] >= starts[2].advanced(by: interval), "An open rail keeps polling")
        polling.setActive(false)
        try! await Task.sleep(for: interval + interval)
        precondition(starts.count == 4, "Collapsing cancels the scheduled refresh")
    }

    @MainActor
    private static func checkKimiTermination() async {
        precondition(!KimiQuota.deferTermination(until: nil) {
            preconditionFailure("There is no Kimi operation to wait for")
        })
        var mayFinish: CheckedContinuation<Void, Never>?
        let operation = Task<(CodexQuota?, ProviderStatus), Never> {
            await withCheckedContinuation { mayFinish = $0 }
            return (nil, ProviderStatus("Kimi", executable: "true"))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while mayFinish == nil && ContinuousClock.now < deadline { await Task.yield() }
        precondition(mayFinish != nil)
        var replied = false
        precondition(KimiQuota.deferTermination(until: operation) { replied = true })
        await Task.yield()
        precondition(!replied, "Quit must wait for the in-progress Kimi operation")
        mayFinish?.resume()
        let replyDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !replied && ContinuousClock.now < replyDeadline { await Task.yield() }
        precondition(replied, "Quit must resume after Kimi finishes")
    }

    static func main() async {
        if CommandLine.arguments.dropFirst().first == KimiQuota.helperFlag {
            KimiQuota.handleHelper(CommandLine.arguments)
        }
        AntigravityQuota.handleStatusLineCallback()
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "--check-antigravity-fixture",
           let timeout = Double(arguments[3]) {
            guard let quota = AntigravityQuota.read(executable: arguments[2], timeout: timeout) else { exit(1) }
            print(quota.gemini.remaining, quota.thirdParty.remaining)
            return
        }
        if arguments.count == 3, arguments[1] == "--check-kimi-helper" {
            let timeouts: (Duration, TimeInterval, Duration) = (.seconds(1), 0.8, .milliseconds(150))
            if let data = await KimiQuota.runLocal(executable: URL(fileURLWithPath: arguments[2]),
                                                  startupTimeout: timeouts.0, requestTimeout: timeouts.1,
                                                  shutdownTimeout: timeouts.2) {
                try! FileHandle.standardOutput.write(contentsOf: data)
            }
            return
        }
        await checkQuotaPolling()
        await checkKimiTermination()
        let visibleOrder = OverlaySubscription.moving("grok", to: 0, in: ["codex", "gemini", "grok"])
        precondition(visibleOrder == ["grok", "codex", "gemini"])
        precondition(OverlaySubscription.moving("grok", to: 2, in: visibleOrder) == ["codex", "gemini", "grok"])
        precondition(OverlaySubscription.replacingVisibleOrder(
            ["codex", "claude", "gemini", "grok"], with: visibleOrder
        ) == ["grok", "claude", "codex", "gemini"])

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
        for provider in ["Claude", "Codex", "Antigravity", "Grok Build", "OpenCode Go", "Kimi"] {
            var snapshot = ProviderQuotaSnapshot<CodexQuota>()
            let installed = ProviderStatus(provider, executable: "sh")
            precondition(installed.showsInSettings && installed.unavailableQuotaLabel == "No quota")
            snapshot.update(nil, status: installed, now: now)
            precondition(snapshot.quota == nil && !snapshot.isStale)

            var signedIn = installed
            signedIn.authorization = "Signed in"
            snapshot.update(live, status: signedIn, now: now)
            for delay in [60.0, 120.0] {
                snapshot.update(nil, status: installed, now: now.addingTimeInterval(delay))
                precondition(snapshot.quota?.remaining == 37 && snapshot.isStale)
                precondition(snapshot.lastUpdated == now && snapshot.status?.showsInSettings == true)
            }
            let recovered = now.addingTimeInterval(180)
            snapshot.update(live, status: signedIn, now: recovered)
            precondition(!snapshot.isStale && snapshot.lastUpdated == recovered)

            for authorization in ["Signed out", "Sign-in required", "Credentials rejected", "API key", "API profile"] {
                snapshot.update(live, status: signedIn, now: now)
                var revoked = installed
                revoked.authorization = authorization
                snapshot.update(nil, status: revoked, now: recovered)
                precondition(snapshot.status?.showsInSettings == true)
                precondition(snapshot.quota == nil && snapshot.lastUpdated == nil && !snapshot.isStale)
            }
            snapshot.update(live, status: signedIn, now: now)
            let removed = ProviderStatus(provider, executable: "quota-rail-missing-cli-fixture")
            snapshot.update(nil, status: removed, now: recovered)
            precondition(snapshot.status?.showsInSettings == false)
            precondition(snapshot.quota == nil && !snapshot.isStale)
        }
        var free = ProviderStatus("Free provider", executable: "sh")
        free.authorization = "Signed in"
        free.subscription = "Free"
        var freeSnapshot = ProviderQuotaSnapshot<CodexQuota>()
        freeSnapshot.update(live, status: free, now: now)
        precondition(freeSnapshot.quota?.remaining == 37 && freeSnapshot.status?.planLabel == "Free")
        let stale = ProviderStatus("Stale provider", executable: "sh")
        let unavailable = ProviderStatus("Unavailable provider", executable: "sh")
        var signedOut = ProviderStatus("Signed-out provider", executable: "sh")
        signedOut.authorization = "Signed out"
        let settingsOrder = ProviderStatus.settingsOrder(
            [signedOut, unavailable, free, stale], quotaOrder: [stale.name, free.name]
        )
        precondition(settingsOrder.map(\.name) == [stale.name, free.name, unavailable.name, signedOut.name])

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
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let authFile = directory.appendingPathComponent("auth.json")
            for contents in [nil, "{}", "{invalid"] as [String?] {
                if let contents { try Data(contents.utf8).write(to: authFile) }
                let expected = contents == "{invalid" ? "No quota" : "Sign-in required"
                var grok = ProviderStatus("Grok Build", executable: "sh")
                var go = ProviderStatus("OpenCode Go", executable: "sh")
                precondition(GrokQuota.readAccessToken(at: authFile, status: &grok) == nil)
                precondition(OpenCodeGoQuota.readKey(at: [authFile], status: &go) == nil)
                precondition(grok.unavailableQuotaLabel == expected && go.unavailableQuotaLabel == expected)
            }
            try grokCredentials.write(to: authFile)
            var grok = ProviderStatus("Grok Build", executable: "sh")
            precondition(GrokQuota.readAccessToken(at: authFile, status: &grok) == "current")
            try Data(#"{"opencode-go":{"key":"fixture"}}"#.utf8).write(to: authFile)
            var go = ProviderStatus("OpenCode Go", executable: "sh")
            precondition(OpenCodeGoQuota.readKey(at: [authFile], status: &go) == "fixture")
        } catch {
            preconditionFailure("Could not prepare authorization fixtures: \(error)")
        }
        let grokPayload = Data("""
            {"config":{"isUnifiedBillingUser":true,"creditUsagePercent":41,
            "currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2027-01-20T14:15:30.192Z"}}}
            """.utf8)
        await checkGrokRecovery()
        await checkGrokHelperLifetime()
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
              "limit7d":{"usedRatio":0.25,"resetAt":"2027-01-20T14:15:30Z"},
              "monthTotal":{"usedRatio":0.5,"resetAt":"2027-02-01T00:00:00Z"},
              "monthCode":{"usedRatio":1,"resetAt":"2027-02-02T00:00:00Z"}
            },"extraUsage":null}}}
            """.utf8)
        let modernWindows = KimiQuota.parse(kimiModern, now: now)?.windows
        precondition(modernWindows?.map(\.label) == ["5h", "7d", "Monthly", "Monthly code"])
        precondition(modernWindows?.map(\.remaining) == [100, 75, 50, 0])
        precondition(modernWindows?.first?.reset == Date(timeIntervalSince1970: 1_800_454_530.192))
        precondition(modernWindows?[1].reset == Date(timeIntervalSince1970: 1_800_454_530))
        precondition(modernWindows?[2].reset == Date(timeIntervalSince1970: 1_801_440_000))
        precondition(modernWindows?[3].reset == Date(timeIntervalSince1970: 1_801_526_400))
        let kimiEmpty = Data(#"{"data":{"kind":"ok","quota":{"usages":{},"extraUsage":null}}}"#.utf8)
        var kimiStatus = ProviderStatus("Kimi", executable: "true", extraPaths: ["/usr/bin"])
        precondition(KimiQuota.apply(kimiEmpty, status: &kimiStatus, now: now) == nil)
        precondition(kimiStatus.authorization == "Signed in")
        precondition(KimiQuota.apply(nil, status: &kimiStatus) == nil)
        let failure = Data(#"{"data":{"kind":"error","message":"upstream unavailable","status":503}}"#.utf8)
        precondition(KimiQuota.apply(failure, status: &kimiStatus) == nil)
        precondition(kimiStatus.authorization == "Signed in")
        let kimiSignedOut = Data(#"{"data":{"kind":"error","message":"No token for this account"}}"#.utf8)
        precondition(KimiQuota.apply(kimiSignedOut, status: &kimiStatus) == nil)
        precondition(kimiStatus.needsSignIn)
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

    private static func checkGrokRecovery() async {
        let reset = Date().addingTimeInterval(3600).ISO8601Format()
        let payload = Data("""
            {"creditUsagePercent":41,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"\(reset)"}}
            """.utf8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        func writeToken(_ token: String, expiry: TimeInterval) {
            let data = Data("""
                {"fixture":{"auth_mode":"oidc","key":"\(token)","expires_at":\(expiry)}}
                """.utf8)
            try! data.write(to: auth, options: .atomic)
        }

        let future = Date().timeIntervalSince1970 + 3600
        for (expiry, firstCode, retryCode, expectedTokens, expectsQuota) in [
            (1.0, 200, 200, ["renewed"], true),
            (future, 401, 200, ["original", "renewed"], true),
            (future, 401, 401, ["original", "renewed"], false),
            (future, 401, 500, ["original", "renewed"], false),
            (future, 401, 0, ["original", "renewed"], false),
            (future, 200, 200, ["original"], true),
            (future, 500, 200, ["original"], false)
        ] {
            writeToken("original", expiry: expiry)
            var refreshes = 0
            var tokens = [String]()
            var status = ProviderStatus("Grok Build", executable: "sh")
            let quota = await GrokQuota.read(at: auth, status: &status, refresh: {
                refreshes += 1
                writeToken("renewed", expiry: future)
            }, request: { token in
                tokens.append(token)
                let code = token == "original" ? firstCode : retryCode
                return code == 0 ? nil : (code, payload)
            })
            precondition(tokens == expectedTokens)
            precondition(refreshes == (expectedTokens.contains("renewed") ? 1 : 0))
            precondition((quota != nil) == expectsQuota)
            if firstCode == 401 {
                precondition(status.authorization == (expectsQuota ? "Signed in" : "Credentials rejected"))
            }
        }
    }

    private static func checkGrokHelperLifetime() async {
        let helper = GrokQuota.SessionRefresh(
            waitLimit: .milliseconds(50), lifetimeLimit: .milliseconds(800),
            pollInterval: .milliseconds(10), arguments: ["30"], executable: { "/bin/sleep" }
        )
        await helper.run()
        let runningAfterWait = await helper.isRunning
        precondition(runningAfterWait, "The quota wait must leave the helper running")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(4))
        while await helper.isRunning, clock.now < deadline {
            try! await Task.sleep(for: .milliseconds(20))
        }
        let runningAfterDeadline = await helper.isRunning
        precondition(!runningAfterDeadline, "The watchdog must stop the helper without another poll")
        print("PASS: Grok caller deadline and independent helper cleanup")
    }

}

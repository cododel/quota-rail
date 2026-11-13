import Darwin
import Foundation

struct AntigravityQuota: Sendable {
    let gemini: CodexQuota
    let thirdParty: CodexQuota

    static func parse(_ data: Data, now: Date = Date()) -> Self? {
        guard let buckets = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        let formatter = ISO8601DateFormatter()
        func quota(_ prefix: String) -> CodexQuota? {
            var windows: [CodexQuota.LimitWindow] = []
            for (suffix, minutes) in [("5h", 300), ("weekly", 10_080)] {
                guard let bucket = buckets["\(prefix)-\(suffix)"],
                      bucket["disabled"] as? Bool != true,
                      let fraction = bucket["remaining_fraction"] as? Double,
                      fraction.isFinite, (0...1).contains(fraction),
                      let resetText = bucket["reset_time"] as? String else { return nil }
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fractional = formatter.date(from: resetText)
                formatter.formatOptions = [.withInternetDateTime]
                guard let reset = fractional ?? formatter.date(from: resetText), reset > now else { return nil }
                windows.append(.init(id: suffix, remaining: Int((fraction * 100).rounded()), minutes: minutes, reset: reset))
            }
            let first = windows[0]
            return CodexQuota(remaining: first.remaining, windowMinutes: first.minutes, reset: first.reset,
                              resetCredits: nil, availableResets: [], usageCreditBalance: nil,
                              unlimitedUsageCredits: false, additionalWindows: Array(windows.dropFirst()))
        }
        guard let gemini = quota("gemini"), let thirdParty = quota("3p") else { return nil }
        return Self(gemini: gemini, thirdParty: thirdParty)
    }

    static func read() -> Self? {
        guard let executable = ProviderStatus.executablePath("agy") else { return nil }
        return read(executable: executable)
    }

    static func read(executable: String, timeout: TimeInterval = 25) -> Self? {
        guard let callback = Bundle.main.executableURL else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-rail-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("quota.json")
        let command = [callback.path, "--capture-antigravity-quota", output.path]
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let settings = ["statusLine": ["type": "command", "command": command, "enabled": true]]
        guard let data = try? JSONSerialization.data(withJSONObject: settings) else { return nil }

        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return nil }
        defer { close(master) }
        let pid = spawnCLI(executable, settings: String(decoding: data, as: UTF8.self),
                           directory: directory.path, terminal: slave)
        close(slave)
        guard let pid else { return nil }
        defer {
            // Keep the group leader unreaped until signals to its group are complete.
            kill(-pid, SIGTERM)
            Thread.sleep(forTimeInterval: 0.2)
            kill(-pid, SIGKILL)
            while waitpid(pid, nil, 0) == -1, errno == EINTR {}
        }

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var terminal = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            let ready = poll(&terminal, 1, 100)
            if ready > 0, terminal.revents & Int16(POLLIN) != 0 {
                _ = buffer.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, $0.count) }
            }
            if let data = try? Data(contentsOf: output), let quota = parse(data) { return quota }
            if ready > 0, terminal.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { break }
            if ready < 0, errno != EINTR { break }
        }
        return nil
    }

    private static func spawnCLI(_ executable: String, settings: String,
                                 directory: String, terminal: Int32) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }

        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory) == 0 else { return nil }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            guard posix_spawn_file_actions_adddup2(&actions, terminal, descriptor) == 0 else { return nil }
        }

        var arguments = [executable, "--settings", settings].map { strdup($0) }
        defer { arguments.forEach { free($0) } }
        guard arguments.allSatisfy({ $0 != nil }) else { return nil }
        arguments.append(nil)
        var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { environment.forEach { free($0) } }
        guard environment.allSatisfy({ $0 != nil }) else { return nil }
        environment.append(nil)
        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &actions, &attributes, &arguments, &environment) == 0
        else { return nil }
        return pid
    }

    static func captureStatusLine(to output: URL) -> Bool {
        let limit = 1_048_576
        var input = Data()
        do {
            while let chunk = try FileHandle.standardInput.read(upToCount: 8192), !chunk.isEmpty {
                guard input.count + chunk.count <= limit else { return false }
                input.append(chunk)
            }
            guard let payload = try JSONSerialization.jsonObject(with: input) as? [String: Any],
                  let quota = payload["quota"] as? [String: Any] else { return false }
            var clean: [String: [String: Any]] = [:]
            for key in ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"] {
                guard let bucket = quota[key] as? [String: Any] else { return false }
                clean[key] = bucket.filter { field, value in
                    switch field {
                    case "remaining_fraction": value is NSNumber
                    case "reset_time": value is String
                    case "disabled": value is Bool
                    default: false
                    }
                }
            }
            let data = try JSONSerialization.data(withJSONObject: clean)
            try data.write(to: output, options: .atomic)
            return true
        } catch { return false }
    }

    static func handleStatusLineCallback() {
        let arguments = CommandLine.arguments
        guard arguments.dropFirst().first == "--capture-antigravity-quota" else { return }
        guard arguments.count == 3 else { exit(1) }
        exit(captureStatusLine(to: URL(fileURLWithPath: arguments[2])) ? 0 : 1)
    }
}

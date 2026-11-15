import Foundation

@MainActor
final class QuotaPolling {
    private let interval: Duration
    private let refresh: () async -> Void
    private let clock = ContinuousClock()
    private var nextRefresh = ContinuousClock.now
    private var active = false
    private var refreshing = false
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(60), refresh: @escaping () async -> Void) {
        self.interval = interval
        self.refresh = refresh
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if active {
            schedule()
        } else if !refreshing {
            task?.cancel()
            task = nil
        }
    }

    func stop() {
        setActive(false)
        task?.cancel()
    }

    private func schedule() {
        guard active, task == nil else { return }
        let deadline = nextRefresh
        task = Task { [weak self, clock] in
            if clock.now < deadline {
                do { try await clock.sleep(until: deadline) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            refreshing = true
            await refresh()
            refreshing = false
            nextRefresh = clock.now.advanced(by: interval)
            task = nil
            schedule()
        }
    }
}

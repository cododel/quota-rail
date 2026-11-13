import SwiftUI

struct CodexDetails: View {
    let quota: CodexQuota
    var providerName = "Codex"
    var limitGroups: [OverlaySubscription.LimitGroup] = []

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.component(.year, from: date)
            == Calendar.current.component(.year, from: Date()) ? "MMM d, HH:mm" : "MMM d, yyyy, HH:mm"
        return formatter.string(from: date)
    }

    private var resetRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(quota.availableResets) { credit in
                Text(credit.expiresAt.map(dateLabel) ?? "Expiration unavailable")
                    .monospacedDigit()
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func windowRows(_ windows: [CodexQuota.LimitWindow]) -> some View {
        ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(window.label).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(window.remaining)% remaining").monospacedDigit()
                    }
                    if let reset = window.reset {
                        Text("Resets \(dateLabel(reset))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(providerName).font(.system(size: 14, weight: .semibold))
            if limitGroups.isEmpty {
                windowRows(quota.windows)
            } else {
                ForEach(limitGroups) { group in
                    Divider()
                    Text(group.name).fontWeight(.medium)
                    windowRows(group.windows)
                }
            }
            if quota.unlimitedUsageCredits || quota.usageCreditBalance != nil {
                Divider()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack {
                        Text("Credits")
                        Spacer()
                        if quota.unlimitedUsageCredits {
                            Text("Unlimited")
                        } else if let balance = quota.usageCreditBalance {
                            Text(balance.formatted(.number.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                    }
                    if !quota.unlimitedUsageCredits, let balance = quota.usageCreditBalance {
                        // Reference estimate matching the quota adapter's $40/1,000-credit basis.
                        Text("≈ \((balance * Decimal(4) / 100).formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            if let count = quota.resetCredits {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Banked resets · \(count)").fontWeight(.medium)
                    if !quota.availableResets.isEmpty {
                        Text("Expires").font(.system(size: 11)).foregroundStyle(.secondary)
                        if quota.availableResets.count <= 6 {
                            resetRows
                        } else {
                            ScrollView { resetRows }.frame(height: 108)
                        }
                    }
                    if count > quota.availableResets.count {
                        Text("Details unavailable for \(count - quota.availableResets.count) resets")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .frame(width: 206, alignment: .leading)
        .padding(12)
    }
}

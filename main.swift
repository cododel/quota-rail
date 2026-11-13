import AppKit
import Combine
import SwiftUI

enum HarnessImages {
    static let directory = AppResources.directory.appendingPathComponent("assets")
    static let claude = NSImage(contentsOf: directory.appendingPathComponent("claude.png"))
    static let antigravity = NSImage(contentsOf: directory.appendingPathComponent("antigravity.png"))
    static let grok = NSImage(contentsOf: directory.appendingPathComponent("grok.svg"))
    static let openCode = NSImage(contentsOf: directory.appendingPathComponent("opencode.svg"))
    static let kimi = NSImage(contentsOf: directory.appendingPathComponent("kimi.svg"))
    static let gpt = NSImage(contentsOf: directory.appendingPathComponent("gpt.png"))
}

struct EdgeShape: Shape {
    var progress: CGFloat
    var bodyHeight: CGFloat = OverlayGeometry.bodyHeight
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Depth leads height so the edge first bulges, then unfolds vertically.
        let depthProgress = 1 - pow(1 - progress, 2)
        let heightProgress = progress * progress
        let depth = max(3, 3 + (OverlayGeometry.width - 3) * depthProgress)
        let span = max(20, 24 + (bodyHeight - 24) * heightProgress)
        let x = rect.maxX
        let y = rect.midY
        let left = x - depth
        let top = y - span / 2
        let bottom = y + span / 2
        let radius = min(depth / 2, span / 4)
        let control = radius * OverlayGeometry.quarterCircleControl
        var path = Path()
        path.move(to: CGPoint(x: x, y: top - radius))
        path.addCurve(
            to: CGPoint(x: x - radius, y: top),
            control1: CGPoint(x: x, y: top - radius + control),
            control2: CGPoint(x: x - radius + control, y: top)
        )
        path.addLine(to: CGPoint(x: left + radius, y: top))
        path.addCurve(
            to: CGPoint(x: left, y: top + radius),
            control1: CGPoint(x: left + radius - control, y: top),
            control2: CGPoint(x: left, y: top + radius - control)
        )
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addCurve(
            to: CGPoint(x: left + radius, y: bottom),
            control1: CGPoint(x: left, y: bottom - radius + control),
            control2: CGPoint(x: left + radius - control, y: bottom)
        )
        path.addLine(to: CGPoint(x: x - radius, y: bottom))
        path.addCurve(
            to: CGPoint(x: x, y: bottom + radius),
            control1: CGPoint(x: x - radius + control, y: bottom),
            control2: CGPoint(x: x, y: bottom + radius - control)
        )
        path.closeSubpath()
        return path
    }
}

struct HoverRegion: Shape {
    let expanded: Bool

    func path(in rect: CGRect) -> Path {
        let size = expanded ? rect.size : CGSize(width: 28, height: 48)
        return Path(CGRect(
            x: rect.maxX - size.width, y: rect.midY - size.height / 2,
            width: size.width, height: size.height
        ))
    }
}

struct SettingsReveal: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let diameter = OverlayGeometry.settingsDiameter * min(1, max(0, progress))
        return Path(ellipseIn: CGRect(
            x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
            width: diameter, height: diameter
        ))
    }
}

struct SettingsGlyph: View, Animatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var borderVisible: Bool
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let amount = min(1, max(0, progress))
        ZStack {
            Circle()
                .trim(from: 0, to: 0.25 + 0.75 * amount)
                .stroke(.black, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .overlay {
                    Circle()
                        .trim(from: 0, to: 0.25 + 0.75 * amount)
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .stroke(Color(white: 0.85).opacity(0.15), lineWidth: 1)
                        .opacity(borderVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: borderVisible)
                        .allowsHitTesting(false)
                }
                .rotationEffect(.degrees(-90))
                .frame(width: OverlayGeometry.settingsDiameter, height: OverlayGeometry.settingsDiameter)
                .opacity(1 - amount)
            Rectangle()
                .fill(.black)
                .overlay {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .scaleEffect(max(0.35, amount))
                        .opacity(min(1, max(0, (amount - 0.3) / 0.3)))
                }
                .clipShape(SettingsReveal(progress: amount))
                .overlay {
                    SettingsReveal(progress: amount)
                        .stroke(Color(white: 0.85).opacity(0.15), lineWidth: 1)
                        .opacity(borderVisible ? amount : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: borderVisible)
                        .allowsHitTesting(false)
                }
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
    }
}

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.2 : 0)
    }
}

@MainActor
final class OverlayState: ObservableObject {
    let releaseUpdates = ReleaseUpdates()
    @Published var codexQuota: CodexQuota?
    @Published var quotaStatus = "Checking Codex quota…"
    @Published var expanded = false
    @Published var borderVisible = false
    @Published var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @Published var selectedSubscription: String?
    @Published var claudeQuota: CodexQuota?
    @Published var providerStatuses: [ProviderStatus] = []
    @Published var kimiQuota: CodexQuota?
    @Published var openCodeGoQuota: CodexQuota?
    @Published var grokQuota: CodexQuota?
    @Published var antigravityQuota: AntigravityQuota?
    @Published var fullDemo = CommandLine.arguments.contains("--full-demo")
        || UserDefaults.standard.bool(forKey: "projector.overlay.fullDemo") {
        didSet {
            UserDefaults.standard.set(fullDemo, forKey: "projector.overlay.fullDemo")
            nextQuotaRefresh = .distantPast
        }
    }
    var nextQuotaRefresh = Date.distantPast
    private let demoStart = Date()
    private static let hiddenSubscriptionsKey = "projector.overlay.hiddenSubscriptions"
    @Published private var hiddenSubscriptions = Set(
        UserDefaults.standard.stringArray(forKey: OverlayState.hiddenSubscriptionsKey) ?? []
    )

    var visibleSubscriptions: [OverlaySubscription] {
        subscriptions.filter { isSubscriptionVisible($0.id) }
    }

    func isSubscriptionVisible(_ id: String) -> Bool {
        !hiddenSubscriptions.contains(id)
    }

    func setSubscriptionVisible(_ id: String, _ visible: Bool) {
        if visible {
            hiddenSubscriptions.remove(id)
        } else {
            if selectedSubscription == id { selectedSubscription = nil }
            hiddenSubscriptions.insert(id)
        }
        UserDefaults.standard.set(hiddenSubscriptions.sorted(), forKey: Self.hiddenSubscriptionsKey)
    }

    var subscriptions: [OverlaySubscription] {
        OverlaySubscription.resolve(codex: codexQuota, antigravity: antigravityQuota, claude: claudeQuota, grok: grokQuota, openCodeGo: openCodeGoQuota, kimi: kimiQuota, fullDemo: fullDemo, now: demoStart)
    }
    var settingsAtMouseDown: Bool?
    @Published var pinned = false
    @Published var settings = false
    @Published var settingsHovered = false
    var closeTask: Task<Void, Never>?
    var hovering = false
}

struct Overlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: OverlayState

    // Springs adapted from boring.notch for a smaller, pointer-driven panel.
    private let openSpring = Animation.spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0)
    private let closeSpring = Animation.spring(response: 0.34, dampingFraction: 1.0, blendDuration: 0)

    private var extraHeight: CGFloat { CGFloat(max(0, state.visibleSubscriptions.count - 3)) * 54 }

    var body: some View {
        ZStack(alignment: .trailing) {
            let contour = EdgeShape(progress: state.expanded ? 1 : 0,
                                    bodyHeight: OverlayGeometry.bodyHeight + extraHeight)
            Rectangle().fill(.black)
                .overlay(alignment: .trailing) {
                    ZStack {
                        ForEach(Array(state.visibleSubscriptions.enumerated()), id: \.element.id) { index, subscription in
                            movingMeter(subscription, row: CGFloat(index) - CGFloat(state.visibleSubscriptions.count - 1) / 2)
                        }
                        if state.subscriptions.isEmpty {
                            Text("—").font(.system(size: 12))
                                .help(state.quotaStatus)
                                .accessibilityLabel(state.quotaStatus)
                        }
                    }
                    .frame(width: 40)
                }
                .clipShape(contour)
                .overlay {
                    contour.stroke(Color(white: 0.85).opacity(0.20), lineWidth: 1)
                        .opacity(state.borderVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.borderVisible)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(!state.expanded)
            Button {
                    let wasOpen = state.settingsAtMouseDown ?? state.settings
                    state.settingsAtMouseDown = nil
                    state.selectedSubscription = nil
                    state.settings = !wasOpen
                } label: {
                    SettingsGlyph(borderVisible: state.borderVisible, progress: settingsExpanded ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9),
                        value: settingsExpanded
                    )
                }
                .buttonStyle(SettingsButtonStyle())
                .help("Overlay settings")
                .onHover { state.settingsHovered = $0 }
                .accessibilityLabel("Overlay settings")
                .padding(.trailing, 0)
                .offset(x: state.expanded ? 0 : 52, y: state.expanded ? OverlayGeometry.settingsCenterY + extraHeight / 2 : 20)
                .animation(
                    reduceMotion ? nil : .spring(response: state.expanded ? 0.44 : 0.32, dampingFraction: 0.95),
                    value: state.expanded
                )
                .allowsHitTesting(state.expanded)
                .accessibilityHidden(!state.expanded)
                .popover(isPresented: $state.settings, arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.releaseUpdates.canCheck {
                            ReleaseUpdateControls(updates: state.releaseUpdates)
                            Divider()
                        }
                        Toggle("Keep overlay visible", isOn: $state.pinned)
                        Toggle("Full demo mode", isOn: $state.fullDemo)
                            .toggleStyle(.checkbox)
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subscriptions")
                                .font(.system(size: 12, weight: .medium))
                            if state.subscriptions.isEmpty {
                                Text(state.quotaStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(state.subscriptions) { subscription in
                                Toggle(isOn: Binding(
                                    get: { state.isSubscriptionVisible(subscription.id) },
                                    set: { state.setSubscriptionVisible(subscription.id, $0) }
                                )) {
                                    Text(subscription.name)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        if !state.hasScreenAccess {
                            Button("Allow Screen Access for Adaptive Outline") {
                                state.hasScreenAccess = CGRequestScreenCaptureAccess()
                            }
                        }
                    }
                    .padding()
                }
        }
        .foregroundStyle(.white)
        .frame(width: 48, height: OverlayGeometry.panelHeight, alignment: .trailing)
        .clipped()
        .contentShape(HoverRegion(expanded: state.expanded))
        .onHover(perform: hoverChanged)
        .onDisappear { state.closeTask?.cancel() }
        .onChange(of: state.settingsHovered) { _, inside in
            if !inside { scheduleCloseIfOutside() }
        }
        .onChange(of: state.selectedSubscription) { _, selection in
            if selection == nil { scheduleCloseIfOutside() }
        }
        .onChange(of: state.settings) { _, isOpen in
            if !isOpen && !state.pinned { scheduleCloseIfOutside() }
        }
    }

    private var settingsExpanded: Bool {
        state.settingsHovered || state.settings
    }

    private func movingMeter(_ subscription: OverlaySubscription, row: CGFloat) -> some View {
        Button {
            state.settingsAtMouseDown = nil
            state.settings = false
            state.selectedSubscription = state.selectedSubscription == subscription.id ? nil : subscription.id
        } label: {
            meter(subscription.quota.remaining, color: subscription.color, provider: subscription.name, mark: subscription.id)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .allowsHitTesting(state.expanded)
            .background {
                IndicatorPopover(isPresented: state.selectedSubscription == subscription.id) {
                    if state.selectedSubscription == subscription.id {
                        state.selectedSubscription = nil
                    }
                } content: {
                    CodexDetails(quota: subscription.quota, providerName: subscription.name, limitGroups: subscription.limitGroups)
                        .foregroundStyle(.white)
                }
            }
            .offset(
                x: state.expanded ? 0 : 48,
                y: row * (state.expanded ? 54 : 8)
            )
            .animation(
                reduceMotion ? nil : .spring(
                    response: state.expanded ? 0.42 + Double(abs(row)) * 0.02 : 0.32,
                    dampingFraction: state.expanded ? 0.94 : 1
                ),
                value: state.expanded
            )
    }

    private func meter(_ percent: Int, color: Color, provider: String, mark: String) -> some View {
        let logoSize: CGFloat = mark == "kimi" || mark == "opencode-go" ? 11 : 14
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Group {
                    let image = switch mark {
                    case "kimi": HarnessImages.kimi
                    case "opencode-go": HarnessImages.openCode
                    case "grok": HarnessImages.grok
                    case "gemini": HarnessImages.antigravity
                    case "claude": HarnessImages.claude
                    default: HarnessImages.gpt
                    }
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(mark == "opencode-go" ? .original : .template)
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: logoSize, height: logoSize)
            }
            .frame(width: 26, height: 26)
            Text("\(percent)%")
                .font(.system(size: 10, weight: .regular).monospacedDigit())
                .frame(height: 14)
        }
        .frame(width: 40, height: 44)
        .help(provider)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider), \(percent) percent remaining")
    }

    private func hoverChanged(_ inside: Bool) {
        state.hovering = inside
        state.closeTask?.cancel()
        if inside {
            withAnimation(reduceMotion ? nil : openSpring) { state.expanded = true }
        } else {
            scheduleCloseIfOutside()
        }
    }

    private func scheduleCloseIfOutside() {
        state.closeTask?.cancel()
        state.closeTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !state.hovering, !state.settingsHovered, !state.pinned, !state.settings, state.selectedSubscription == nil else { return }
            withAnimation(reduceMotion ? nil : closeSpring) { state.expanded = false }
        }
    }
}

@MainActor
final class OverlayDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var contrastMonitor: ContrastMonitor?
    private var quotaTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var panelClickMonitor: Any?
    private let state = OverlayState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let bounds = screen.frame
        let panel = NSPanel(
            contentRect: NSRect(x: bounds.maxX - 48, y: bounds.midY - OverlayGeometry.panelHeight / 2, width: 48, height: OverlayGeometry.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: Overlay(state: state))
        panel.orderFrontRegardless()
        self.panel = panel
        state.releaseUpdates.start()
        // Preserve the settings popover state during its native dismissal.
        panelClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.type == .leftMouseDown {
                self.state.settingsAtMouseDown = self.state.settings
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.state.settingsAtMouseDown = nil
                }
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let state = self?.state, state.settings || state.selectedSubscription != nil else { return }
                state.settings = false
                state.selectedSubscription = nil
            }
        }
        contrastMonitor = ContrastMonitor(state: state, panel: panel)
        contrastMonitor?.start()
        quotaTask = Task { [state] in
            while !Task.isCancelled {
                if !state.fullDemo && Date() >= state.nextQuotaRefresh {
                    async let codex = Task.detached(priority: .utility) {
                        var status = ProviderStatus("Codex", executable: "codex")
                        let result = CodexQuota.read(status: &status)
                        status.quotaAvailable = (try? result.get()) != nil
                        return (result, status)
                    }.value
                    async let antigravity = Task.detached(priority: .utility) {
                        await ProviderStatus.read("Antigravity", executable: "agy") { _ in AntigravityQuota.read() }
                    }.value
                    async let claude = Task.detached(priority: .utility) {
                        await ProviderStatus.read("Claude", executable: "claude") { ClaudeQuota.read(status: &$0) }
                    }.value
                    async let grok = ProviderStatus.read("Grok Build", executable: "grok") { await GrokQuota.read(status: &$0) }
                    async let openCodeGo = ProviderStatus.read("OpenCode Go", executable: "opencode") { await OpenCodeGoQuota.read(status: &$0) }
                    let kimiBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code/bin").path
                    async let kimi = ProviderStatus.read("Kimi", executable: "kimi", extraPaths: [kimiBin]) {
                        await KimiQuota.read(status: &$0)
                    }
                    let ((codexResult, codexStatus), (antigravityResult, antigravityStatus),
                         (claudeResult, claudeStatus), (grokResult, grokStatus),
                         (openCodeGoResult, openCodeGoStatus), (kimiResult, kimiStatus)) =
                        await (codex, antigravity, claude, grok, openCodeGo, kimi)
                    guard !Task.isCancelled else { return }
                    if !state.fullDemo {
                        switch codexResult {
                        case .success(let quota):
                            state.codexQuota = quota
                            state.quotaStatus = "\(quota.label) · \(quota.remaining)% remaining"
                        case .failure(let error):
                            state.codexQuota = nil
                            state.quotaStatus = error.rawValue
                        }
                        state.antigravityQuota = antigravityResult
                        state.claudeQuota = claudeResult
                        state.grokQuota = grokResult
                        state.openCodeGoQuota = openCodeGoResult
                        state.kimiQuota = kimiResult
                        state.providerStatuses = [claudeStatus, codexStatus, antigravityStatus,
                                                  grokStatus, openCodeGoStatus, kimiStatus]
                        state.nextQuotaRefresh = Date().addingTimeInterval(60)
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let panelClickMonitor {
            NSEvent.removeMonitor(panelClickMonitor)
            self.panelClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        quotaTask?.cancel()
        contrastMonitor?.stop()
        state.closeTask?.cancel()
    }
}

@main
enum OverlayDemo {
    @MainActor
    static func main() {
        AppResources.migratePreferences()
        if CommandLine.arguments.contains("--export-contour") {
            print(OverlayGeometry.drawing())
            return
        }
        if CommandLine.arguments.contains("--check-antigravity-quota") {
            guard let result = AntigravityQuota.read() else {
                print("Antigravity quota unavailable")
                exit(1)
            }
            for (name, quota) in [("Gemini", result.gemini), ("Claude/GPT", result.thirdParty)] {
                for window in quota.windows {
                    print("\(name) · \(window.label) · \(window.remaining)% remaining · \(window.reset?.ISO8601Format() ?? "unknown")")
                }
            }
            return
        }
        if CommandLine.arguments.contains("--check-codex-quota") {
            var status = ProviderStatus("Codex", executable: "codex")
            switch CodexQuota.read(status: &status) {
            case .success(let quota):
                print("\(quota.label) · \(quota.remaining)% remaining")
                if let label = quota.usageCreditLabel { print(label) }
                if let credits = quota.resetCredits { print("Available reset credits: \(credits)") }
                for credit in quota.availableResets {
                    print("Expires: \(credit.expiresAt?.ISO8601Format() ?? "unavailable")")
                }
                if let reset = quota.reset { print("Reset: \(reset.ISO8601Format())") }
            case .failure(let error):
                print(error.rawValue)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = OverlayDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

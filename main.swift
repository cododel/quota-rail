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
    var appearance: CGFloat = 1
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, appearance) }
        set { progress = newValue.first; appearance = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        // Depth leads height so the edge first bulges, then unfolds vertically.
        let depthProgress = 1 - pow(1 - progress, 2)
        let heightProgress = progress * progress
        let depth = max(3, 3 + (OverlayGeometry.width - 3) * depthProgress)
        let span = 6 + (24 + (bodyHeight - 24) * heightProgress - 6) * appearance
        let x = rect.maxX
        let y = rect.midY
        let left = x - depth
        let top = y - span / 2
        let bottom = y + span / 2
        let radius = 3 + (min(depth / 2, span / 4) - 3) * appearance
        let control = radius * OverlayGeometry.quarterCircleControl
        let flare = radius * appearance
        let flareControl = control * appearance
        var path = Path()
        path.move(to: CGPoint(x: x, y: top - flare))
        path.addCurve(
            to: CGPoint(x: x - flare, y: top),
            control1: CGPoint(x: x, y: top - flare + flareControl),
            control2: CGPoint(x: x - flare + flareControl, y: top)
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
        path.addLine(to: CGPoint(x: x - flare, y: bottom))
        path.addCurve(
            to: CGPoint(x: x, y: bottom + flare),
            control1: CGPoint(x: x - flare + flareControl, y: bottom),
            control2: CGPoint(x: x, y: bottom + flare - flareControl)
        )
        path.closeSubpath()
        return path
    }
}

struct HoverRegion: Shape {
    let expanded: Bool

    func path(in rect: CGRect) -> Path {
        let size = expanded ? rect.size : CGSize(width: 3, height: 48)
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
                        .animation(reduceMotion ? nil : OverlayMotion.outline, value: borderVisible)
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
                        .animation(reduceMotion ? nil : OverlayMotion.outline, value: borderVisible)
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
    @Published var codexSnapshot = ProviderQuotaSnapshot<CodexQuota>()
    @Published var quotaStatus = "Checking Codex quota…"
    @Published var expanded = false
    @Published var borderVisible = false
    @Published var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @Published var selectedSubscription: String?
    @Published var claudeSnapshot = ProviderQuotaSnapshot<CodexQuota>()
    var providerStatuses: [ProviderStatus] {
        [claudeSnapshot.status, codexSnapshot.status, antigravitySnapshot.status,
         grokSnapshot.status, openCodeGoSnapshot.status, kimiSnapshot.status].compactMap { $0 }
    }

    func staleQuotaDate(for provider: String) -> Date? {
        guard !fullDemo else { return nil }
        switch provider {
        case "Claude": return claudeSnapshot.isStale ? claudeSnapshot.lastUpdated : nil
        case "Codex": return codexSnapshot.isStale ? codexSnapshot.lastUpdated : nil
        case "Antigravity": return antigravitySnapshot.isStale ? antigravitySnapshot.lastUpdated : nil
        case "Grok Build": return grokSnapshot.isStale ? grokSnapshot.lastUpdated : nil
        case "OpenCode Go": return openCodeGoSnapshot.isStale ? openCodeGoSnapshot.lastUpdated : nil
        case "Kimi": return kimiSnapshot.isStale ? kimiSnapshot.lastUpdated : nil
        default: return nil
        }
    }
    @Published var kimiSnapshot = ProviderQuotaSnapshot<CodexQuota>()
    @Published var openCodeGoSnapshot = ProviderQuotaSnapshot<CodexQuota>()
    @Published var grokSnapshot = ProviderQuotaSnapshot<CodexQuota>()
    @Published var antigravitySnapshot = ProviderQuotaSnapshot<AntigravityQuota>()
    private static let forceFullDemo = CommandLine.arguments.contains("--full-demo")
    let showsDemoSettings = CommandLine.arguments.contains("--demo") && !OverlayState.forceFullDemo

    @Published var fullDemo = OverlayState.forceFullDemo
        || (CommandLine.arguments.contains("--demo")
            && UserDefaults.standard.bool(forKey: "projector.overlay.fullDemo")) {
        didSet {
            if showsDemoSettings {
                UserDefaults.standard.set(fullDemo, forKey: "projector.overlay.fullDemo")
            }
            nextQuotaRefresh = .distantPast
        }
    }
    var nextQuotaRefresh = Date.distantPast
    private let demoStart = Date()
    private static let hiddenSubscriptionsKey = "projector.overlay.hiddenSubscriptions"
    @Published private var hiddenSubscriptions = Set(
        UserDefaults.standard.stringArray(forKey: OverlayState.hiddenSubscriptionsKey) ?? []
    )

    private var orderKey: String {
        fullDemo ? "projector.overlay.demoSubscriptionOrder" : "projector.overlay.subscriptionOrder"
    }
    @Published private var subscriptionOrders: [String: [String]] = [:]

    private var subscriptionOrder: [String] {
        subscriptionOrders[orderKey] ?? UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }

    func rememberSubscriptions(_ ids: [String]) {
        let order = subscriptionOrder
        let updated = order + ids.filter { !order.contains($0) }
        if updated != order { saveSubscriptionOrder(updated) }
    }

    func reorderSubscriptions(_ visibleIDs: [String]) {
        saveSubscriptionOrder(OverlaySubscription.replacingVisibleOrder(subscriptionOrder, with: visibleIDs))
    }

    private func saveSubscriptionOrder(_ order: [String]) {
        subscriptionOrders[orderKey] = order
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    var orderedSubscriptions: [OverlaySubscription] {
        let available = subscriptions
        let order = subscriptionOrder
        let ordered = order.compactMap { id in available.first { $0.id == id } }
        return ordered + available.filter { !order.contains($0.id) }
    }

    var visibleSubscriptions: [OverlaySubscription] {
        orderedSubscriptions.filter { isSubscriptionVisible($0.id) }
    }

    func isSubscriptionVisible(_ id: String) -> Bool {
        fullDemo || !hiddenSubscriptions.contains(id)
    }

    func setSubscriptionVisible(_ id: String, _ visible: Bool) {
        guard !fullDemo else { return }
        if visible {
            hiddenSubscriptions.remove(id)
        } else {
            if selectedSubscription == id { selectedSubscription = nil }
            hiddenSubscriptions.insert(id)
        }
        UserDefaults.standard.set(hiddenSubscriptions.sorted(), forKey: Self.hiddenSubscriptionsKey)
    }

    var subscriptions: [OverlaySubscription] {
        OverlaySubscription.resolve(codex: codexSnapshot.quota, antigravity: antigravitySnapshot.quota, claude: claudeSnapshot.quota, grok: grokSnapshot.quota, openCodeGo: openCodeGoSnapshot.quota, kimi: kimiSnapshot.quota, fullDemo: fullDemo, now: demoStart)
    }
    @Published var pinned = false
    @Published var settings = false
    @Published var settingsHovered = false
    @Published var settingsHoverEnabled = false
    var expansionID = UUID()
    var closeTask: Task<Void, Never>?
    var settingsHoverTask: Task<Void, Never>?
    var hovering = false
}

struct Overlay: View {
    @State private var appearance: CGFloat = 0
    @State private var entryOffset: CGFloat = 3
    @State private var appearanceComplete = false
    @GestureState private var trackingRing = false
    @State private var draggedID: String?
    @State private var dragOffset: CGFloat = 0
    @State private var proposedOrder: [String] = []
    private let rowPitch: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: OverlayState


    private var extraHeight: CGFloat { CGFloat(max(0, state.visibleSubscriptions.count - 3)) * 54 }

    var body: some View {
        ZStack(alignment: .trailing) {
            let contour = EdgeShape(progress: state.expanded ? 1 : 0,
                                    bodyHeight: OverlayGeometry.bodyHeight + extraHeight,
                                    appearance: appearance)
            Rectangle().fill(.black)
                .overlay(alignment: .trailing) {
                    ZStack {
                        ForEach(Array(state.visibleSubscriptions.enumerated()), id: \.element.id) { index, subscription in
                            movingMeter(subscription, index: index)
                        }
                        if state.subscriptions.isEmpty {
                            Text("—").font(.system(size: 12))
                                .help(state.quotaStatus)
                                .accessibilityLabel(state.quotaStatus)
                        }
                    }
                    .frame(width: 40, height: 44)
                    .coordinateSpace(name: "quotaRailRows")
                }
                .clipShape(contour)
                .overlay {
                    contour.stroke(Color(white: 0.85).opacity(0.20), lineWidth: 1)
                        .opacity(state.borderVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : OverlayMotion.outline, value: state.borderVisible)
                        .allowsHitTesting(false)
                }
                .offset(x: entryOffset)
                .accessibilityHidden(!state.expanded)
            Button {
                    state.selectedSubscription = nil
                    state.settings.toggle()
                } label: {
                    SettingsGlyph(borderVisible: state.borderVisible, progress: settingsExpanded ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : OverlayMotion.settings,
                        value: settingsExpanded
                    )
                }
                .buttonStyle(SettingsButtonStyle())
                .help("Overlay settings")
                .onHover(perform: settingsHoverChanged)
                .accessibilityLabel("Overlay settings")
                .background {
                    RailPopover(isPresented: state.settings) {
                        state.settings = false
                    } content: {
                        VStack(alignment: .leading, spacing: 12) {
                            if state.releaseUpdates.canCheck {
                                ReleaseUpdateControls(updates: state.releaseUpdates)
                                Divider()
                            }
                            Toggle("Keep overlay visible", isOn: $state.pinned)
                            if state.showsDemoSettings {
                                Toggle("Full demo mode", isOn: $state.fullDemo)
                                    .toggleStyle(.checkbox)
                            }
                            Divider()
                            let installedProviders = ProviderStatus.settingsOrder(state.providerStatuses, quotaOrder: state.orderedSubscriptions.map(\.name))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Subscriptions")
                                    .font(.system(size: 12, weight: .medium))
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if state.fullDemo {
                                            ForEach(state.orderedSubscriptions) { subscription in
                                                subscriptionRow(subscription.name, subscription: subscription, detail: nil)
                                            }
                                        } else if state.providerStatuses.isEmpty {
                                            Text("Checking providers…").foregroundStyle(.secondary)
                                        } else if installedProviders.isEmpty {
                                            Text("No supported CLIs found").foregroundStyle(.secondary)
                                        } else {
                                            ForEach(installedProviders, id: \.name) { provider in
                                                let subscription = state.subscriptions.first { $0.name == provider.name }
                                                subscriptionRow(provider.name, subscription: subscription,
                                                                detail: subscription == nil ? provider.unavailableQuotaLabel : (provider.quotaAvailable ? provider.planLabel : "Stale"))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: CGFloat(max(24, (state.fullDemo ? state.subscriptions.count : installedProviders.count) * 24)))
                            }
                            if !state.hasScreenAccess {
                                Button("Allow Screen Access for Adaptive Outline") {
                                    state.hasScreenAccess = CGRequestScreenCaptureAccess()
                                }
                            }
                            Divider()
                            Button("Quit") {
                                NSApp.terminate(nil)
                            }
                        }
                        .frame(width: 268, alignment: .leading)
                        .padding()
                        .foregroundStyle(.white)
                        .overlay(alignment: .topTrailing) {
                            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            let displayVersion = version.flatMap { $0.isEmpty ? nil : $0 }
                            Text(displayVersion.map { "v\($0)" } ?? "Preview")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.20))
                                .padding(.top, 5)
                                .padding(.trailing, 8)
                                .allowsHitTesting(false)
                                .accessibilityLabel(displayVersion.map { "Version \($0)" } ?? "Preview build")
                        }
                    }
                }
                .padding(.trailing, 0)
                .offset(x: state.expanded ? 0 : 52, y: state.expanded ? OverlayGeometry.settingsCenterY + extraHeight / 2 : 20)
                .animation(
                    reduceMotion ? nil : (state.expanded ? OverlayMotion.expand : OverlayMotion.collapse),
                    value: state.expanded
                )
                .allowsHitTesting(state.settingsHoverEnabled)
                .accessibilityHidden(!state.settingsHoverEnabled)
        }
        .foregroundStyle(.white)
        .frame(width: 48, height: OverlayGeometry.panelHeight, alignment: .trailing)
        .clipped()
        .task {
            if reduceMotion {
                entryOffset = 0
                appearance = 1
                appearanceComplete = true
                return
            }
            withAnimation(OverlayMotion.enter, completionCriteria: .removed) {
                entryOffset = 0
            } completion: {
                withAnimation(OverlayMotion.unfold, completionCriteria: .removed) {
                    appearance = 1
                } completion: {
                    appearanceComplete = true
                }
            }
        }
        .contentShape(HoverRegion(expanded: state.expanded))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let bounds = CGRect(x: 0, y: 0, width: 48, height: OverlayGeometry.panelHeight)
                let region = HoverRegion(expanded: state.expanded).path(in: bounds)
                hoverChanged(region.contains(location))
            case .ended:
                hoverChanged(false)
            }
        }
        .onChange(of: state.subscriptions.map(\.id), initial: true) { _, ids in
            state.rememberSubscriptions(ids)
        }
        .onChange(of: state.fullDemo) { _, _ in
            state.rememberSubscriptions(state.subscriptions.map(\.id))
            finishDrag(commit: false)
        }
        .onChange(of: state.visibleSubscriptions.map(\.id)) { _, ids in
            if draggedID != nil && Set(ids) != Set(proposedOrder) { finishDrag(commit: false) }
        }
        .onChange(of: trackingRing) { _, tracking in
            if !tracking { finishDrag(commit: false) }
        }
        .onDisappear {
            state.closeTask?.cancel()
            settingsHoverChanged(false)
        }
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

    private func subscriptionRow(_ name: String, subscription: OverlaySubscription?, detail: String?) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { subscription.map { state.isSubscriptionVisible($0.id) } ?? false },
                set: { visible in
                    if let subscription { state.setSubscriptionVisible(subscription.id, visible) }
                }
            )) {
                Text(name).lineLimit(1)
            }
            .toggleStyle(.checkbox)
            .disabled(subscription == nil || state.fullDemo)

            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(detail)
            }
        }
        .frame(height: 20)
    }

    private func toggleDetails(_ id: String) {
        guard state.expanded else { return }
        state.settings = false
        state.selectedSubscription = state.selectedSubscription == id ? nil : id
    }

    private func finishDrag(commit: Bool) {
        guard draggedID != nil else { return }
        withAnimation(reduceMotion ? nil : OverlayMotion.reorder) {
            if commit { state.reorderSubscriptions(proposedOrder) }
            draggedID = nil
            proposedOrder = []
            dragOffset = 0
        }
        scheduleCloseIfOutside()
    }

    private func ringGesture(_ id: String, row: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("quotaRailRows"))
            .updating($trackingRing) { _, tracking, _ in tracking = true }
            .onChanged { value in
                let ids = state.visibleSubscriptions.map(\.id)
                guard state.expanded, ids.count > 1, let index = ids.firstIndex(of: id),
                      abs(value.translation.height) >= 5 || draggedID == id
                else { return }
                if draggedID == nil {
                    let startY = value.startLocation.y - row * rowPitch
                    guard (0...26).contains(startY) else { return }
                    draggedID = id
                    state.closeTask?.cancel()
                    state.settings = false
                    state.selectedSubscription = nil
                }
                guard draggedID == id else { return }
                let position = min(CGFloat(ids.count - 1), max(0, CGFloat(index) + value.translation.height / rowPitch))
                dragOffset = (position - CGFloat(index)) * rowPitch
                let target = Int(position.rounded())
                withAnimation(reduceMotion ? nil : OverlayMotion.reorder) {
                    proposedOrder = OverlaySubscription.moving(id, to: target, in: ids)
                }
            }
            .onEnded { value in
                if draggedID == id {
                    finishDrag(commit: true)
                } else if hypot(value.translation.width, value.translation.height) < 5 {
                    toggleDetails(id)
                }
            }
    }

    private func movingMeter(_ subscription: OverlaySubscription, index: Int) -> some View {
        let staleSince = state.staleQuotaDate(for: subscription.name)
        let dragging = draggedID == subscription.id
        let slot = dragging ? index : proposedOrder.firstIndex(of: subscription.id) ?? index
        let row = CGFloat(slot) - CGFloat(state.visibleSubscriptions.count - 1) / 2
        return meter(subscription.quota.remaining, color: subscription.color, provider: subscription.name, mark: subscription.id, isStale: staleSince != nil)
            .contentShape(Rectangle())
            .gesture(ringGesture(subscription.id, row: CGFloat(index) - CGFloat(state.visibleSubscriptions.count - 1) / 2))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleDetails(subscription.id) }
            .allowsHitTesting(state.expanded)
            .background {
                RailPopover(isPresented: state.selectedSubscription == subscription.id, anchorInsetFromTop: 13) {
                    if state.selectedSubscription == subscription.id {
                        state.selectedSubscription = nil
                    }
                } content: {
                    CodexDetails(quota: subscription.quota, providerName: subscription.name, limitGroups: subscription.limitGroups, staleSince: staleSince)
                        .foregroundStyle(.white)
                }
            }
            .offset(
                x: state.expanded ? 0 : 48,
                y: row * (state.expanded ? rowPitch : 8) + (dragging ? dragOffset : 0)
            )
            .zIndex(dragging ? 1 : 0)
            .animation(
                reduceMotion ? nil : (state.expanded ? OverlayMotion.expand : OverlayMotion.collapse),
                value: state.expanded
            )
    }

    private func meter(_ percent: Int, color: Color, provider: String, mark: String, isStale: Bool) -> some View {
        let logoSize: CGFloat = mark == "kimi" || mark == "opencode-go" ? 11 : 14
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : OverlayMotion.quota, value: percent)
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
            Text(isStale ? "\(percent)%*" : "\(percent)%")
                .font(.system(size: 10, weight: .regular).monospacedDigit())
                .frame(height: 14)
        }
        .frame(width: 40, height: 44)
        .help(isStale ? "\(provider) · Stale quota" : provider)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isStale ? "\(provider), last known quota \(percent) percent remaining" : "\(provider), \(percent) percent remaining")
    }

    private func settingsHoverChanged(_ inside: Bool) {
        state.settingsHoverTask?.cancel()
        state.settingsHoverTask = nil
        guard inside, state.settingsHoverEnabled else {
            state.settingsHovered = false
            return
        }
        state.settingsHoverTask = Task { @MainActor [weak state] in
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard let state, state.settingsHoverEnabled else { return }
            state.settingsHovered = true
            state.settingsHoverTask = nil
        }
    }

    private func hoverChanged(_ inside: Bool) {
        guard appearanceComplete else { return }
        guard state.hovering != inside else { return }
        state.hovering = inside
        state.closeTask?.cancel()
        if inside {
            guard !state.expanded else { return }
            let expansionID = UUID()
            state.expansionID = expansionID
            withAnimation(reduceMotion ? nil : OverlayMotion.expand, completionCriteria: .removed) {
                state.expanded = true
            } completion: {
                guard state.expanded, state.expansionID == expansionID else { return }
                state.settingsHoverEnabled = true
            }
        } else {
            scheduleCloseIfOutside()
        }
    }

    private func scheduleCloseIfOutside() {
        state.closeTask?.cancel()
        state.closeTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard draggedID == nil, !state.hovering, !state.settingsHovered, !state.pinned, !state.settings, state.selectedSubscription == nil else { return }
            state.settingsHoverEnabled = false
            settingsHoverChanged(false)
            withAnimation(reduceMotion ? nil : OverlayMotion.collapse) { state.expanded = false }
        }
    }
}

@MainActor
final class OverlayDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var contrastMonitor: ContrastMonitor?
    private var quotaTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private let state = OverlayState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
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
                        if case .failure(.apiProfile) = result { status.authorization = "API profile" }
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
                            state.quotaStatus = "\(quota.label) · \(quota.remaining)% remaining"
                        case .failure(let error):
                            state.quotaStatus = error.rawValue
                        }
                        state.codexSnapshot.update(try? codexResult.get(), status: codexStatus)
                        state.antigravitySnapshot.update(antigravityResult, status: antigravityStatus)
                        state.claudeSnapshot.update(claudeResult, status: claudeStatus)
                        state.grokSnapshot.update(grokResult, status: grokStatus)
                        state.openCodeGoSnapshot.update(openCodeGoResult, status: openCodeGoStatus)
                        state.kimiSnapshot.update(kimiResult, status: kimiStatus)
                        state.nextQuotaRefresh = Date().addingTimeInterval(60)
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        quotaTask?.cancel()
        contrastMonitor?.stop()
        state.closeTask?.cancel()
        state.settingsHoverTask?.cancel()
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

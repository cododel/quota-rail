import AppKit
import SwiftUI

struct RailPopover<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    var anchorInsetFromTop: CGFloat? = nil
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ anchor: NSView, context: Context) {
        let coordinator = context.coordinator
        guard isPresented else {
            coordinator.close()
            return
        }
        coordinator.scheduleShow(from: anchor, insetFromTop: anchorInsetFromTop, content: content(), dismiss: dismiss)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator {
        private let popover = NSPopover()
        private var pendingShow: Task<Void, Never>?
        private var clickMonitor: Any?
        private var dismiss: (() -> Void)?

        init() {
            popover.behavior = .applicationDefined
        }

        func scheduleShow(from anchor: NSView, insetFromTop: CGFloat?, content: Content, dismiss: @escaping () -> Void) {
            pendingShow?.cancel()
            // AppKit positions the popover window after SwiftUI finishes updating the anchor.
            pendingShow = Task { @MainActor [weak self, weak anchor] in
                guard !Task.isCancelled, let self, let anchor else { return }
                self.pendingShow = nil
                self.show(from: anchor, insetFromTop: insetFromTop, content: content, dismiss: dismiss)
            }
        }

        private func show(from anchor: NSView, insetFromTop: CGFloat?, content: Content, dismiss: @escaping () -> Void) {
            guard let window = anchor.window, let panelContent = window.contentView,
                  let screen = window.screen else { return }
            self.dismiss = dismiss
            let host: NSHostingController<Content>
            if let existing = popover.contentViewController as? NSHostingController<Content> {
                host = existing
                host.rootView = content
            } else {
                host = NSHostingController(rootView: content)
                popover.contentViewController = host
            }
            // Place the popover using its final content size on the first layout pass.
            let available = screen.visibleFrame.size
            let measured = host.sizeThatFits(in: available)
            guard measured.width.isFinite, measured.height.isFinite,
                  measured.width > 0, measured.height > 0 else { return }
            let contentSize = NSSize(width: min(measured.width, available.width),
                                     height: min(measured.height, available.height))
            if popover.contentSize != contentSize {
                popover.contentSize = contentSize
            }
            // Keep the arrow beside the rail and aligned with the trigger.
            let inset = insetFromTop ?? anchor.bounds.height / 2
            let anchorY = anchor.isFlipped ? anchor.bounds.minY + inset : anchor.bounds.maxY - inset
            let anchorCenter = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchorY), to: panelContent)
            let attachment = CGRect(x: panelContent.bounds.maxX - OverlayGeometry.width,
                                    y: anchorCenter.y - 0.5, width: 1, height: 1)
            if popover.isShown {
                if popover.positioningRect != attachment {
                    popover.positioningRect = attachment
                }
                return
            }
            popover.show(relativeTo: attachment, of: panelContent, preferredEdge: .minX)
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
            ) { [weak self, weak anchor] event in
                guard let self, let anchor else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.dismiss?()
                        return nil
                    }
                    return event
                }
                if let popoverWindow = self.popover.contentViewController?.view.window,
                   event.window === popoverWindow {
                    return event
                }
                if event.type == .leftMouseDown, event.window === anchor.window,
                   anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                    return event
                }
                self.dismiss?()
                return event
            }
        }

        func close() {
            pendingShow?.cancel()
            pendingShow = nil
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
            dismiss = nil
            if popover.isShown { popover.close() }
        }
    }
}

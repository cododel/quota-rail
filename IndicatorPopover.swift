import AppKit
import SwiftUI

struct IndicatorPopover<Content: View>: NSViewRepresentable {
    let isPresented: Bool
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
        coordinator.show(from: anchor, content: content(), dismiss: dismiss)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator {
        private let popover = NSPopover()
        private var clickMonitor: Any?
        private var dismiss: (() -> Void)?

        init() {
            popover.behavior = .applicationDefined
        }

        func show(from anchor: NSView, content: Content, dismiss: @escaping () -> Void) {
            guard anchor.window != nil else { return }
            self.dismiss = dismiss
            let host: NSHostingController<Content>
            if let existing = popover.contentViewController as? NSHostingController<Content> {
                host = existing
                host.rootView = content
            } else {
                host = NSHostingController(rootView: content)
                popover.contentViewController = host
            }
            guard !popover.isShown else { return }

            // Align the arrow with the ring, above the percentage label.
            let ringCenter = anchor.isFlipped ? 13.0 : anchor.bounds.height - 13.0
            let attachment = CGRect(x: 0, y: ringCenter, width: 1, height: 1)
            popover.show(relativeTo: attachment, of: anchor, preferredEdge: .minX)
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
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
            dismiss = nil
            if popover.isShown { popover.close() }
        }
    }
}

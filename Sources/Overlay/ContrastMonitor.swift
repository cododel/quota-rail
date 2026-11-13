import AppKit
import ScreenCaptureKit

@MainActor
final class ContrastMonitor {
    private let state: OverlayState
    private weak var panel: NSPanel?
    private var task: Task<Void, Never>?

    init(state: OverlayState, panel: NSPanel) {
        self.state = state
        self.panel = panel
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func sample() async {
        let hasScreenAccess = CGPreflightScreenCaptureAccess()
        if state.hasScreenAccess != hasScreenAccess {
            state.hasScreenAccess = hasScreenAccess
        }
        guard hasScreenAccess else {
            state.borderVisible = false
            return
        }
        guard let panel, let screen = panel.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { return }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !ownApps.isEmpty else { return }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.width = 40
            configuration.height = 188
            // ScreenCaptureKit uses a top-left, display-local source rectangle.
            configuration.sourceRect = CGRect(
                x: panel.frame.maxX - 40 - screen.frame.minX,
                y: screen.frame.maxY - (panel.frame.midY + 94),
                width: 40, height: 188
            )
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard !Task.isCancelled, let ratio = Self.contrastAgainstBlack(image) else { return }
            // Hysteresis prevents flicker around the threshold.
            state.borderVisible = ratio < (state.borderVisible ? 2.5 : 2.0)
        } catch {
            guard !Task.isCancelled else { return }
            state.borderVisible = false
        }
    }

    static func contrastAgainstBlack(_ image: CGImage) -> Double? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * linear(pixels[index])
                + 0.7152 * linear(pixels[index + 1])
                + 0.0722 * linear(pixels[index + 2])
        }
        return (total / Double(width * height) + 0.05) / 0.05
    }
}

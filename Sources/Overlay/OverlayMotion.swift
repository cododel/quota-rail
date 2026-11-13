import SwiftUI

enum OverlayMotion {
    // Gentle acceleration and a long settle, shared by all rail transitions.
    static func curve(duration: Double) -> Animation {
        .timingCurve(0.22, 0.0, 0.18, 1.0, duration: duration)
    }

    static let enter = curve(duration: 0.42)
    static let unfold = curve(duration: 0.58)
    static let expand = curve(duration: 0.48)
    static let collapse = curve(duration: 0.36)
    static let settings = curve(duration: 0.36)
    static let outline = curve(duration: 0.2)
    static let quota = curve(duration: 0.36)
    static let reorder = curve(duration: 0.22)
}

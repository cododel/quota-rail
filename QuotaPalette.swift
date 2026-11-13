import SwiftUI

enum QuotaPalette {
    static func color(remaining: Int) -> Color {
        let percent = Double(min(100, max(0, remaining)))
        let softLeaf = 0x98D486
        let goldenYellow = 0xE8C65A
        let orange = 0xF28C45
        let coralRed = 0xEF5C61

        switch percent {
        case 52...: return blend(softLeaf, softLeaf, progress: 0)
        case 48..<52: return blend(goldenYellow, softLeaf, progress: (percent - 48) / 4)
        case 22..<48: return blend(goldenYellow, goldenYellow, progress: 0)
        case 18..<22: return blend(orange, goldenYellow, progress: (percent - 18) / 4)
        case 7..<18: return blend(orange, orange, progress: 0)
        case 3..<7: return blend(coralRed, orange, progress: (percent - 3) / 4)
        default: return blend(coralRed, coralRed, progress: 0)
        }
    }

    private static func blend(_ from: Int, _ to: Int, progress: Double) -> Color {
        // Smoothstep joins the flat zones with zero slope at both ends, matching the mockup.
        let amount = progress * progress * (3 - 2 * progress)
        func channel(_ shift: Int) -> Double {
            let start = Double((from >> shift) & 0xFF)
            let end = Double((to >> shift) & 0xFF)
            return (start + (end - start) * amount) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
}

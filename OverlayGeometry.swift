import SwiftUI

enum OverlayGeometry {
    static let width: CGFloat = 40
    static let bodyHeight: CGFloat = 188
    static let settingsDiameter: CGFloat = 26
    static let settingsCenterY = bodyHeight / 2 + width / 2
    // Cubic circle approximation; shared verbatim by the rendered path and SVG.
    static let quarterCircleControl: CGFloat = 4 * (sqrt(2) - 1) / 3

    static func drawing() -> String {
        let path = EdgeShape(progress: 1).path(in: CGRect(x: 0, y: -20, width: width, height: 228))
        var commands: [String] = []
        func point(_ p: CGPoint) -> String { "\(p.x),\(p.y)" }
        path.cgPath.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: commands.append("M\(point(e.points[0]))")
            case .addLineToPoint: commands.append("L\(point(e.points[0]))")
            case .addQuadCurveToPoint: commands.append("Q\(point(e.points[0])) \(point(e.points[1]))")
            case .addCurveToPoint: commands.append("C\(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2]))")
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        let contour = commands.joined(separator: " ")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 -100 1200 1200">
        <defs>
          <path id="contour" d="\(contour)"/>
          <marker id="arrow" viewBox="0 0 6 6" refX="3" refY="3" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M6 3L0 0V6Z" fill="#245bc5"/></marker>
          <style>text{font-family:Arial,sans-serif;fill:#18202b} .dim{stroke:#245bc5;stroke-width:.4;fill:none} .guide{stroke:#7b9cd9;stroke-width:.3;stroke-dasharray:2 2;fill:none} .label{font-size:4px;fill:#245bc5} .measure{marker-start:url(#arrow);marker-end:url(#arrow)}</style>
        </defs>
        <rect y="-100" width="1200" height="1200" fill="#fafbfc"/>
        <text x="48" y="48" font-size="26">Projector · overlay contour</text>
        <text x="48" y="76" font-size="14">Coordinates in pt · origin at body top-left · screen edge x = 40 · exported from Swift path</text>
        <text x="64" y="120" font-size="18">REST</text><text x="254" y="120" font-size="18">SETTINGS HOVER</text>
        <g transform="translate(64 200) scale(2.4)">
          <rect x="-8" y="-25" width="48" height="253" fill="#bdc0ca"/>
          <use href="#contour" fill="black"/>
          <path d="M20 195 A13 13 0 0 1 33 208" fill="none" stroke="black" stroke-width="2" stroke-linecap="round"/>
        </g>
        <g transform="translate(254 200) scale(2.4)">
          <rect x="-8" y="-25" width="48" height="253" fill="#bdc0ca"/>
          <use href="#contour" fill="black"/><circle cx="20" cy="208" r="13" fill="black"/>
          <text x="20" y="212" fill="white" style="fill:white" font-size="14" text-anchor="middle">⚙</text>
        </g>
        <g transform="translate(520 200) scale(2.4)">
          <use href="#contour" fill="#edf2fc" stroke="#245bc5" stroke-width=".5"/>
          <path class="guide" d="M20 -28V230 M-10 0H65 M-10 188H65 M40 -30V235"/>
          <g class="guide"><circle cx="20" cy="-20" r="20"/><circle cx="20" cy="20" r="20"/><circle cx="20" cy="168" r="20"/><circle cx="20" cy="208" r="20"/></g>
          <circle cx="20" cy="208" r="13" class="guide"/>
          <path d="M20 195 A13 13 0 0 1 33 208" fill="none" stroke="black" stroke-width="2" stroke-linecap="round"/>
          <g fill="#245bc5"><circle cx="40" cy="-20" r="1"/><circle cx="20" cy="0" r="1"/><circle cx="0" cy="20" r="1"/><circle cx="0" cy="168" r="1"/><circle cx="20" cy="188" r="1"/><circle cx="40" cy="208" r="1"/></g>
          <path class="dim measure" d="M0 -30H40 M-12 0V188"/>
          <text class="label" x="20" y="-33" text-anchor="middle">40</text><text class="label" x="-15" y="94" text-anchor="end">188</text>
          <path class="dim" d="M20 208H68 M40 188H68 M20 0H68 M0 20H68"/>
          <text class="label" x="70" y="209">C = (20, 208)</text><text class="label" x="70" y="189">R20 concave</text><text class="label" x="70" y="1">S-join (20, 0)</text><text class="label" x="70" y="21">R20 convex</text>
        </g>
        <text x="830" y="310" font-size="18">LOWER JOIN · 6×</text>
        <g transform="translate(850 -780) scale(6)">
          <path d="M20 188 C31.045694996615872 188 40 196.95430500338412 40 208" class="dim"/>
          <circle cx="20" cy="208" r="20" class="guide"/><circle cx="20" cy="208" r="13" class="guide"/>
          <path class="guide" d="M-3 208H44 M20 185V231"/>
          <path d="M20 195 A13 13 0 0 1 33 208" stroke="black" stroke-width="2" fill="none" stroke-linecap="round"/>
          <circle cx="20" cy="208" r=".6" fill="#245bc5"/>
          <path class="dim measure" d="M20 208H33"/><text class="label" x="25" y="213">R13</text>
        </g>
        <text x="830" y="620" font-size="14">Arc: −90° → 0° · 2 pt round stroke</text>
        <text x="830" y="645" font-size="14">Disk: Ø26 · shared center (20, 208)</text>
        <text x="830" y="670" font-size="14">Clearance: 6 pt to arc ink / 7 pt to disk</text>
        <text x="48" y="820" font-size="14">All four bends: cubic quarter-circles, k = 4(√2 − 1)/3. Tangents match at each join (G1).</text>
        <text x="48" y="846" font-size="14">Cubic radial error &lt; 0.006 pt at R20. Body 40 × 188; total contour height 228; settings center y = 208.</text>
        </svg>
        """
    }
}

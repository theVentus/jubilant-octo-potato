import SwiftUI
import UIKit
import CoreText

/// Banknote-style guilloche: sharp hairlines give Liquid Glass something to refract.
struct Guilloche: View {
    var ink: Color

    var body: some View {
        Canvas { ctx, size in
            // Full-height modulated wave lines, so every glass element has detail behind it.
            let rows = 46
            for j in 0..<rows {
                let y0 = size.height * Double(j) / Double(rows - 1)
                var p = Path()
                let amp = 9 + 7 * sin(Double(j) * 0.35)
                for i in 0...180 {
                    let x = size.width * Double(i) / 180
                    let y = y0 + amp * sin(x / size.width * .pi * 6 + Double(j) * 0.5)
                        + 4 * sin(x / size.width * .pi * 17 - Double(j))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(p, with: .color(ink.opacity(0.55)), lineWidth: 0.6)
            }
            // Two rosettes (closed hypotrochoids), like the medallions on a note.
            func rosette(center c: CGPoint, R: Double, ratio: (Int, Int), d: Double, width: Double, alpha: Double) {
                let (p, q) = ratio            // (R-r)/r = p/q  -> closes after q turns
                let r = R * Double(q) / Double(p + q)
                var path = Path()
                let steps = 3000
                for i in 0...steps {
                    let t = Double(i) / Double(steps) * 2 * .pi * Double(q)
                    let x = (R - r) * cos(t) + d * r * cos((R - r) / r * t)
                    let y = (R - r) * sin(t) - d * r * sin((R - r) / r * t)
                    let pt = CGPoint(x: c.x + x, y: c.y + y)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: width)
            }
            let top = CGPoint(x: size.width * 0.78, y: size.height * 0.13)
            rosette(center: top, R: size.width * 0.34, ratio: (17, 5), d: 0.9, width: 0.7, alpha: 0.9)
            rosette(center: top, R: size.width * 0.24, ratio: (11, 4), d: 0.8, width: 0.6, alpha: 0.7)
            let low = CGPoint(x: size.width * 0.2, y: size.height * 0.8)
            rosette(center: low, R: size.width * 0.42, ratio: (19, 6), d: 0.85, width: 0.7, alpha: 0.8)
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Outline of a string as a Shape (Core Text glyph paths), so text itself can be glass.
struct GlyphShape: Shape {
    let text: String
    var weight: UIFont.Weight = .heavy

    func path(in rect: CGRect) -> Path {
        let base = UIFont.systemFont(ofSize: 200, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 200) } ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let cg = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    cg.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
                }
            }
        }
        let b = cg.boundingBoxOfPath
        guard b.width > 0, b.height > 0 else { return Path() }
        let s = min(rect.width / b.width, rect.height / b.height)
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: s, y: -s)
            .translatedBy(x: -b.midX, y: -b.midY)
        return Path(cg).applying(t)
    }
}

/// Active currency's symbol rendered as a solid piece of clear glass.
struct GlassGlyph: View {
    let code: String

    private var glyph: String {
        let s = Currency.symbol(code)
        return (s.isEmpty || s.count > 2) ? String(code.prefix(3)) : s
    }

    var body: some View {
        Color.clear
            .frame(width: 150, height: 118)
            .glassEffect(.clear.interactive(), in: GlyphShape(text: glyph))
            .id(code)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityHidden(true)
    }
}

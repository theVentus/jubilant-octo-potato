import SwiftUI
import UIKit
import CoreText

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

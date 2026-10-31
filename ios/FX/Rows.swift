import SwiftUI
import UIKit

// MARK: - Rows

/// One currency line. Fixed rhythm: every row has the same minimum height whether or not it is
/// active, so the glass lens drawn behind the active row glides without the list jumping.
struct CurrencyRow: View {
    let code: String
    let isActive: Bool
    let amount: String
    let detail: String?

    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 60

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: code, size: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(code)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                Text(Currency.name(code))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Never squeeze the code; long expressions shrink the amount instead.
            .frame(minWidth: 72, alignment: .leading)
            .layoutPriority(0)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    let sym = Currency.symbol(code)
                    if !sym.isEmpty {
                        Text(sym)
                            .font(.system(size: symbolSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Text(amount)
                        .font(.system(size: amountSize, weight: isActive ? .semibold : .regular, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(Color.primary.opacity(isActive ? 1 : 0.82))
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.45)
                // Inactive amounts sit a step down; scaling (not a font swap) keeps the morph smooth.
                .scaleEffect(isActive ? 1 : 0.84, anchor: .trailing)

                if let detail {
                    Text(detail)
                        .font(.system(.footnote, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .layoutPriority(1)
        }
        .frame(minHeight: rowHeight)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flag badge

/// Circular flag. The flag emoji is rasterised once, cropped to its opaque rectangle and drawn
/// aspect-filled into the circle, so every flag fills the badge edge to edge (no emoji margins).
struct FlagBadge: View {
    let code: String
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if let img = FlagArt.image(code) {
                Circle().fill(Color(white: 0.9))
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Circle().fill(Color.primary.opacity(dark ? 0.14 : 0.07))
                Text(fallbackGlyph)
                    .font(.system(size: size * (fallbackGlyph.count > 1 ? 0.34 : 0.46),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                                  lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(dark ? 0.35 : 0.10), radius: size * 0.06, y: size * 0.03)
        .accessibilityHidden(true)
    }

    private var fallbackGlyph: String {
        let s = Currency.symbol(code)
        if !s.isEmpty && s.count <= 2 { return s }
        return String(code.prefix(3))
    }
}

// MARK: - Flag rasterisation + colour sampling

/// Rendered flag art, shared by FlagBadge and Backdrop.
final class FlagArtEntry {
    let image: UIImage?
    /// Up to three dominant colours, most prominent first (sRGB, 0...1).
    let palette: [SIMD3<Double>]
    init(image: UIImage?, palette: [SIMD3<Double>]) {
        self.image = image
        self.palette = palette
    }
}

enum FlagArt {
    private static let cache = NSCache<NSString, FlagArtEntry>()

    static func image(_ code: String) -> UIImage? { entry(code).image }
    static func palette(_ code: String) -> [SIMD3<Double>] { entry(code).palette }

    static func entry(_ code: String) -> FlagArtEntry {
        if let e = cache.object(forKey: code as NSString) { return e }
        let e = render(code) ?? FlagArtEntry(image: nil, palette: [])
        cache.setObject(e, forKey: code as NSString)
        return e
    }

    private static func render(_ code: String) -> FlagArtEntry? {
        guard let flag = Currency.flag(code) else { return nil }
        let str = NSAttributedString(string: flag, attributes: [.font: UIFont.systemFont(ofSize: 96)])
        let textSize = str.size()
        guard textSize.width > 4, textSize.height > 4 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let canvas = CGSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let raw = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            str.draw(at: .zero)
        }
        guard let cg = raw.cgImage else { return nil }

        let w = cg.width, h = cg.height
        guard w > 8, h > 8, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        // Opaque bounding box (row 0 of the buffer is the top of the image).
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 200 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX > minX + 8, maxY > minY + 8 else { return nil }
        // Trim the anti-aliased rim.
        minX += 2; minY += 2; maxX -= 2; maxY -= 2
        let bw = maxX - minX + 1, bh = maxY - minY + 1

        // A real flag is a mostly-solid wide rectangle; an unknown region renders as two letters.
        var solid = 0, samples: [SIMD3<Double>] = []
        let step = max(1, Int((Double(bw * bh) / 900).squareRoot()))
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3])
                if a > 200 {
                    solid += 1
                    samples.append(SIMD3(Double(px[i]) / a, Double(px[i + 1]) / a, Double(px[i + 2]) / a))
                }
                x += step
            }
            y += step
        }
        let gridCount = ((bw + step - 1) / step) * ((bh + step - 1) / step)
        let aspect = Double(bw) / Double(bh)
        guard gridCount > 0, Double(solid) / Double(gridCount) > 0.6, aspect > 0.9, aspect < 2.4 else { return nil }

        guard let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: bw, height: bh)) else { return nil }
        let image = UIImage(cgImage: cropped, scale: 2, orientation: .up)
        return FlagArtEntry(image: image, palette: dominantColours(samples, k: 3))
    }

    /// Tiny deterministic k-means (farthest-point seeding). Returns clusters by weight.
    static func dominantColours(_ pts: [SIMD3<Double>], k: Int) -> [SIMD3<Double>] {
        guard !pts.isEmpty else { return [] }
        func d2(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
            let v = a - b
            return (v * v).sum()
        }
        var centres: [SIMD3<Double>] = [pts[pts.count / 2]]
        while centres.count < k {
            var best = 0.0, bestP = pts[0]
            for p in pts {
                let m = centres.map { d2($0, p) }.min() ?? 0
                if m > best { best = m; bestP = p }
            }
            if best < 0.01 { break }
            centres.append(bestP)
        }
        var counts = [Int](repeating: 0, count: centres.count)
        for _ in 0..<8 {
            var sums = [SIMD3<Double>](repeating: .zero, count: centres.count)
            counts = [Int](repeating: 0, count: centres.count)
            for p in pts {
                var bi = 0, bd = Double.greatestFiniteMagnitude
                for (i, c) in centres.enumerated() {
                    let d = d2(c, p)
                    if d < bd { bd = d; bi = i }
                }
                sums[bi] += p
                counts[bi] += 1
            }
            for i in centres.indices where counts[i] > 0 {
                centres[i] = sums[i] / Double(counts[i])
            }
        }
        let total = Double(pts.count)
        return centres.indices
            .filter { Double(counts[$0]) / total > 0.04 }
            .sorted { counts[$0] > counts[$1] }
            .map { centres[$0] }
    }
}

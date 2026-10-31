import SwiftUI
import UIKit

// MARK: - Backdrop

/// "ambient" (default): two or three soft colour fields sampled from the active currency's flag,
/// over a near-black / near-white base, with a gentle vignette. "system": flat.
struct Backdrop: View {
    var activeCode: String
    @AppStorage("bg") private var style = "ambient"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        let ambient = style != "system"
        ZStack {
            (dark ? Color.black : Color(white: 0.965))
            if ambient {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion)) { ctx in
                    let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        AmbientFields(colours: Self.fieldColours(activeCode, dark: dark), dark: dark, t: t)
                            .id(activeCode)
                            .transition(.opacity)
                    }
                }
                Vignette(dark: dark)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: activeCode)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Flag palette tuned for the scheme: low-chroma colours (white, black, grey stripes) are dropped
    /// unless nothing else is left, chroma is capped so nothing glows, and brightness is pinned to
    /// a band that keeps primary/secondary text legible.
    static func fieldColours(_ code: String, dark: Bool) -> [Color] {
        let pal = FlagArt.palette(code)
        var hsb: [(h: CGFloat, s: CGFloat, b: CGFloat)] = pal.map { c in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
                .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return (h: h, s: s, b: b)
        }
        let chromatic = hsb.filter { $0.s > 0.18 && $0.b > 0.15 }
        if !chromatic.isEmpty { hsb = chromatic }
        if hsb.isEmpty {
            // No flag (e.g. XAU, XDR): a quiet cool neutral.
            hsb = [(0.6, 0.12, 0.6), (0.62, 0.08, 0.5)]
        }
        return hsb.prefix(3).map { c in
            if dark {
                return Color(hue: Double(c.h),
                             saturation: Double(min(c.s, 0.85)),
                             brightness: Double(0.42 + 0.3 * c.b))
            } else {
                return Color(hue: Double(c.h),
                             saturation: Double(min(c.s, 0.7) * 0.85),
                             brightness: Double(max(c.b, 0.88)))
            }
        }
    }
}

/// Large radial colour fields, no hard edges. `t` drives an extremely slow drift (period ~50–80s).
private struct AmbientFields: View {
    let colours: [Color]
    let dark: Bool
    let t: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let r = max(w, h)
            let c0 = colours.first ?? .clear
            let c1 = colours.count > 1 ? colours[1] : c0
            let c2 = colours.count > 2 ? colours[2] : c1
            let a0 = dark ? 0.62 : 0.55
            let a1 = dark ? 0.46 : 0.42
            let a2 = dark ? 0.38 : 0.34
            ZStack {
                field(c0, alpha: a0,
                      at: UnitPoint(x: 0.12 + 0.05 * sin(t / 9), y: 0.02 + 0.03 * cos(t / 11)),
                      radius: r * 0.78)
                field(c1, alpha: a1,
                      at: UnitPoint(x: 0.98 + 0.04 * cos(t / 12), y: 0.30 + 0.04 * sin(t / 8.5)),
                      radius: r * 0.62)
                field(c2, alpha: a2,
                      at: UnitPoint(x: 0.30 + 0.06 * sin(t / 10), y: 1.02 + 0.03 * cos(t / 13)),
                      radius: r * 0.72)
            }
            .frame(width: w, height: h)
        }
        .compositingGroup()
    }

    private func field(_ c: Color, alpha: Double, at p: UnitPoint, radius: CGFloat) -> some View {
        Rectangle().fill(
            RadialGradient(stops: [
                .init(color: c.opacity(alpha), location: 0),
                .init(color: c.opacity(alpha * 0.55), location: 0.35),
                .init(color: c.opacity(alpha * 0.18), location: 0.7),
                .init(color: c.opacity(0), location: 1),
            ], center: p, startRadius: 0, endRadius: radius)
        )
    }
}

/// Calms the edges and the lower half (where the keypad floats) so content stays legible.
private struct Vignette: View {
    let dark: Bool

    var body: some View {
        ZStack {
            if dark {
                RadialGradient(colors: [.clear, .black.opacity(0.45)],
                               center: UnitPoint(x: 0.5, y: 0.35), startRadius: 120, endRadius: 760)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0), location: 0.35),
                    .init(color: .black.opacity(0.35), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                // Light: a soft white veil through the list area keeps contrast; edges keep a hint of colour.
                RadialGradient(colors: [.white.opacity(0.42), .white.opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 520)
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.4),
                    .init(color: .white.opacity(0.35), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

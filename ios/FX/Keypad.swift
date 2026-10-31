import SwiftUI
import UIKit

// MARK: - Motion

/// Timing for the keypad open/collapse choreography. `-slowmo YES` stretches everything ×6
/// (durations and delays) so CI can record morph frames.
enum KeypadMotion {
    static var factor: Double { UserDefaults.standard.bool(forKey: "slowmo") ? 6 : 1 }

    /// Capsule → keypad glass morph: deliberate spring with a gentle settle.
    static var open: Animation { .spring(duration: 0.65 * factor, bounce: 0.18) }
    /// Keypad → capsule glass morph: calm, no overshoot.
    static var close: Animation { .spring(duration: 0.5 * factor, bounce: 0) }

    /// Key labels arriving after the glass has started to grow.
    static var labelIn: Animation { .spring(duration: 0.38 * factor, bounce: 0.12) }
    /// Key labels leaving before the glass collapses.
    static var labelOut: Animation { .easeOut(duration: 0.12 * factor) }
    /// Collapsed capsule content (flag + amount) fading in / out.
    static var capsuleIn: Animation { .easeOut(duration: 0.28 * factor) }
    static var capsuleOut: Animation { .easeOut(duration: 0.1 * factor) }

    /// Per-row label stagger.
    static var rowStagger: Double { 0.035 * factor }
    /// Gap between the capsule content fading out and the glass starting to open.
    static var openLead: Double { 0.05 * factor }
    /// Gap between the glass starting to open and the first row of labels appearing.
    static var labelsLag: Double { 0.14 * factor }
    /// Gap between labels fading out and the glass starting to collapse.
    static var closeLead: Double { 0.09 * factor }
    /// Gap between the glass starting to collapse and the capsule content appearing.
    static var capsuleLag: Double { 0.16 * factor }
}

// MARK: - Glass control layer

struct KeypadDock: View {
    @Binding var open: Bool
    let code: String
    let display: String
    /// Kept for call-site compatibility; the dock times itself with `KeypadMotion`.
    let anim: Animation
    let ns: Namespace.ID
    let onHeight: (CGFloat) -> Void
    let onKey: (Key) -> Void

    /// Drives the glass morph; trails `open` so labels can leave before the glass collapses.
    @State private var expanded: Bool
    @State private var labelsShown: Bool
    @State private var capsuleShown: Bool
    /// Generation token: a newer open/close request cancels pending steps of an older one.
    @State private var generation = 0

    private let rows: [[Key]] = [
        [.clear, .percent, .back, .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .op("×")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−")],
        [.digit("1"), .digit("2"), .digit("3"), .op("+")],
        [.digit("00"), .digit("0"), .dot, .equals],
    ]

    init(open: Binding<Bool>,
         code: String,
         display: String,
         anim: Animation,
         ns: Namespace.ID,
         onHeight: @escaping (CGFloat) -> Void,
         onKey: @escaping (Key) -> Void) {
        self._open = open
        self.code = code
        self.display = display
        self.anim = anim
        self.ns = ns
        self.onHeight = onHeight
        self.onKey = onKey
        let isOpen = open.wrappedValue
        self._expanded = State(initialValue: isOpen)
        self._labelsShown = State(initialValue: isOpen)
        self._capsuleShown = State(initialValue: !isOpen)
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            if expanded {
                VStack(spacing: 8) {
                    Button { open = false } label: {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, height: 22)
                            .opacity(labelsShown ? 1 : 0)
                            .animation(labelAnimation(delay: Double(rows.count) * KeypadMotion.rowStagger),
                                       value: labelsShown)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("dock", in: ns)

                    ForEach(rows.indices, id: \.self) { r in
                        // Bottom-up: labels rise out of the capsule the glass grew from.
                        let delay = Double(rows.count - 1 - r) * KeypadMotion.rowStagger
                        HStack(spacing: 8) {
                            ForEach(rows[r].indices, id: \.self) { c in
                                let k = rows[r][c]
                                KeyButton(key: k,
                                          id: "key-\(r)-\(c)",
                                          ns: ns,
                                          revealed: labelsShown,
                                          revealAnimation: labelAnimation(delay: delay)) { onKey(k) }
                            }
                        }
                    }
                }
            } else {
                Button { open = true } label: {
                    HStack(spacing: 10) {
                        FlagBadge(code: code, size: 28)
                        Text(display)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Image(systemName: "keyboard.chevron.compact.down")
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(capsuleShown ? 1 : 0)
                    .scaleEffect(capsuleShown ? 1 : 0.92)
                    .animation(capsuleShown ? KeypadMotion.capsuleIn : KeypadMotion.capsuleOut,
                               value: capsuleShown)
                    .padding(.leading, 12)
                    .padding(.trailing, 18)
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("dock", in: ns)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { h in
            onHeight(h)
        }
        .onChange(of: open) { _, isOpen in
            choreograph(toOpen: isOpen)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: expanded)
    }

    private func labelAnimation(delay: Double) -> Animation {
        labelsShown ? KeypadMotion.labelIn.delay(delay) : KeypadMotion.labelOut
    }

    /// Open: capsule content fades → glass morphs open → labels stagger in.
    /// Close: labels fade → glass morphs closed → capsule content fades in.
    private func choreograph(toOpen: Bool) {
        generation &+= 1
        let token = generation
        if toOpen {
            capsuleShown = false
            after(KeypadMotion.openLead, token) {
                withAnimation(KeypadMotion.open) { expanded = true }
                after(KeypadMotion.labelsLag, token) { labelsShown = true }
            }
        } else {
            labelsShown = false
            after(KeypadMotion.closeLead, token) {
                withAnimation(KeypadMotion.close) { expanded = false }
                after(KeypadMotion.capsuleLag, token) { capsuleShown = true }
            }
        }
    }

    private func after(_ seconds: Double, _ token: Int, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard token == generation else { return }
            body()
        }
    }
}

struct KeyButton: View {
    @Environment(\.colorScheme) private var scheme
    let key: Key
    let id: String
    let ns: Namespace.ID
    var revealed: Bool = true
    var revealAnimation: Animation = .default
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(foreground)
                .shadow(color: shadowColor, radius: 1.5, y: scheme == .dark ? 0.5 : 0)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.82)
                .blur(radius: revealed ? 0 : 3)
                .animation(revealAnimation, value: revealed)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .capsule)
        .glassEffectID(id, in: ns)
    }

    private var glass: Glass {
        if key == .equals { return .regular.tint(.orange).interactive() }
        // Clear glass over the calm (masked) backdrop; a faint white lift in light mode keeps edges readable.
        return scheme == .dark ? .clear.interactive() : .clear.tint(.white.opacity(0.12)).interactive()
    }

    private var shadowColor: Color {
        if key == .equals { return .black.opacity(0.18) }
        return scheme == .dark ? .black.opacity(0.28) : .white.opacity(0.45)
    }

    private var foreground: Color {
        if key == .equals { return .white }
        if key.isOperator { return .orange }
        if key.isFunction { return .secondary }
        return .primary
    }

    @ViewBuilder private var label: some View {
        switch key {
        case .digit(let d): Text(d)
        case .dot: Text(Locale.current.decimalSeparator ?? ".")
        case .op(let o): Image(systemName: Self.symbol(o))
        case .back: Image(systemName: "delete.left")
        case .clear: Text("AC")
        case .equals: Image(systemName: "equal")
        case .percent: Image(systemName: "percent")
        }
    }

    private static func symbol(_ o: Character) -> String {
        switch o { case "÷": "divide"; case "×": "multiply"; case "−": "minus"; default: "plus" }
    }
}

// MARK: - Calm surface under the keypad

extension View {
    /// Apply to the ScrollView that sits under the keypad's `safeAreaBar`. Scroll content fades out
    /// over ~70pt just above the keypad's top edge and is fully hidden behind the keypad, so the
    /// clear keys only refract the ambient backdrop. `height` is the dock's measured height
    /// (from `KeypadDock(onHeight:)`); the hidden band follows it as the dock opens/collapses.
    func keypadUnderlay(height: CGFloat) -> some View {
        modifier(KeypadUnderlay(height: height))
    }
}

private struct KeypadUnderlay: ViewModifier {
    let height: CGFloat
    /// Bottom safe-area inset of the scroll view: the safeAreaBar (keypad) plus the home indicator.
    @State private var barInset: CGFloat = 0

    private static let fade: CGFloat = 48

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { inset in
                barInset = inset
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                    Color.clear
                        .frame(height: max(barInset, 0))
                }
                .animation(KeypadMotion.close, value: barInset)
                .animation(KeypadMotion.close, value: height)
                .ignoresSafeArea()
            }
    }
}

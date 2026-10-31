import SwiftUI
import UIKit

// MARK: - Glass control layer

struct KeypadDock: View {
    @Binding var open: Bool
    let code: String
    let display: String
    let anim: Animation
    let ns: Namespace.ID
    let onKey: (Key) -> Void

    private let rows: [[Key]] = [
        [.clear, .percent, .back, .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .op("×")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−")],
        [.digit("1"), .digit("2"), .digit("3"), .op("+")],
        [.digit("00"), .digit("0"), .dot, .equals],
    ]

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            if open {
                VStack(spacing: 8) {
                    Button { withAnimation(anim) { open = false } } label: {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, height: 22)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("dock", in: ns)

                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r].indices, id: \.self) { c in
                                let k = rows[r][c]
                                KeyButton(key: k, id: "key-\(r)-\(c)", ns: ns) { onKey(k) }
                            }
                        }
                    }
                }
            } else {
                Button { withAnimation(anim) { open = true } } label: {
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
    }
}

struct KeyButton: View {
    @Environment(\.colorScheme) private var scheme
    let key: Key
    let id: String
    let ns: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 28, weight: scheme == .dark ? .semibold : .regular, design: .rounded))
                .shadow(color: scheme == .dark ? .black.opacity(0.35) : .white.opacity(0.6), radius: 2)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .capsule)
        .glassEffectID(id, in: ns)
    }

    private var glass: Glass {
        if key == .equals { return .regular.tint(.orange).interactive() }
        // Clear glass shows the guilloche bending through each key; needs bold, bright glyphs.
        return scheme == .dark ? .clear.interactive() : .clear.tint(.white.opacity(0.12)).interactive()
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
        case .op(let o): Image(systemName: Self.symbol(o)).fontWeight(.medium)
        case .back: Image(systemName: "delete.left")
        case .clear: Text("AC")
        case .equals: Image(systemName: "equal").fontWeight(.semibold)
        case .percent: Image(systemName: "percent")
        }
    }

    private static func symbol(_ o: Character) -> String {
        switch o { case "÷": "divide"; case "×": "multiply"; case "−": "minus"; default: "plus" }
    }
}


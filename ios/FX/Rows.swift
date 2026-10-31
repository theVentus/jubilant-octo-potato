import SwiftUI
import UIKit

// MARK: - Rows

struct CurrencyRow: View {
    let code: String
    let isActive: Bool
    let amount: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: code, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(Currency.name(code))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Currency.symbol(code))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(amount)
                        .font(.system(size: isActive ? 32 : 26, weight: isActive ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                if let detail {
                    Text(detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

struct FlagBadge: View {
    let code: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let f = Currency.flag(code) {
                Text(f).font(.system(size: size * 1.6))
            } else {
                Circle().fill(.thinMaterial)
                Text(String(code.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
}


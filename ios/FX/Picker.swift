import SwiftUI
import UIKit

// MARK: - Picker (add, remove, reorder)

struct CurrencyPicker: View {
    let selected: [String]
    let all: [String]
    let toggle: (String) -> Void
    let move: (IndexSet, Int) -> Void
    let delete: (IndexSet) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) || Currency.name($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty && !selected.isEmpty {
                    Section("Your currencies") {
                        ForEach(selected, id: \.self) { code in
                            PickerRowLabel(code: code) {
                                let sym = Currency.symbol(code)
                                if !sym.isEmpty {
                                    Text(sym)
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    }
                }
                Section(query.isEmpty ? "All currencies" : "Results") {
                    ForEach(filtered, id: \.self) { row($0) }
                }
            }
            .searchable(text: $query, prompt: "Search currency")
            .navigationTitle("Currencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ code: String) -> some View {
        let on = selected.contains(code)
        return Button { toggle(code) } label: {
            PickerRowLabel(code: code) {
                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.rect)
        }
        .tint(.primary)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Shared row layout for the picker: badge, name over code, trailing accessory.
private struct PickerRowLabel<Accessory: View>: View {
    let code: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: code, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(Currency.name(code))
                    .font(.body)
                    .lineLimit(1)
                Text(code)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.vertical, 3)
    }
}

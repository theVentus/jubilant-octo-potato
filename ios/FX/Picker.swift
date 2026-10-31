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
                            HStack(spacing: 12) {
                                FlagBadge(code: code, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Currency.name(code))
                                    Text(code).font(.caption).foregroundStyle(.secondary)
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
        Button { toggle(code) } label: {
            HStack(spacing: 12) {
                FlagBadge(code: code, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Currency.name(code))
                    Text(code).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(code) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(code) ? Color.accentColor : Color.secondary.opacity(0.6))
            }
        }
        .tint(.primary)
    }
}


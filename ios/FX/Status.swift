import SwiftUI
import UIKit

// MARK: - Freshness text

/// Compact "how long ago" text, e.g. "just now", "14 min ago", "9 h ago", "3 d ago".
enum Freshness {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) d ago"
    }

    /// "Live" for the hourly keyed source, "Daily rates" for the keyless ones.
    static func sourceLabel(_ source: String?) -> String {
        source == "CurrencyBeacon" ? "Live" : "Daily rates"
    }
}

// MARK: - Status line

struct StatusLine: View {
    let store: RatesStore

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .symbolEffect(.rotate, isActive: store.isRefreshing)
                        .foregroundStyle(tint)
                    Text(label(now: context.date))
                        .contentTransition(.opacity)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if store.rates.source == "Exchange Rate API" {
                    Link("Rates By Exchange Rate API", destination: URL(string: "https://www.exchangerate-api.com")!)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: store.status)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch store.status {
        case .refreshing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .keyRejected: return "exclamationmark.triangle"
        case .quotaExceeded: return "gauge.with.dots.needle.100percent"
        case .limitReached: return "hourglass"
        case .idle: return store.isLive ? "bolt.fill" : "checkmark.circle"
        }
    }

    private var tint: Color {
        switch store.status {
        case .keyRejected, .quotaExceeded: return .orange
        case .idle where store.isLive: return .green
        default: return .secondary
        }
    }

    private func label(now: Date) -> String {
        let source = Freshness.sourceLabel(store.rates.source)
        guard let updated = store.rates.updated else {
            switch store.status {
            case .refreshing: return "Getting rates…"
            case .offline: return "Offline · no rates yet"
            default: return "No rates yet"
            }
        }
        let ago = Freshness.ago(updated, now: now)
        switch store.status {
        case .refreshing: return "Updating…"
        case .offline: return "Offline · \(source.lowercased()) from \(ago)"
        case .keyRejected: return "API key rejected · updated \(ago)"
        case .quotaExceeded: return "Live quota used up · updated \(ago)"
        case .limitReached: return "No refreshes left today · updated \(ago)"
        case .idle: return "\(source) · updated \(ago)"
        }
    }
}

// MARK: - Toolbar refresh button

struct RefreshButton: View {
    let store: RatesStore
    @Binding var showSettings: Bool
    @State private var successes = 0

    private var exhausted: Bool { store.remainingToday == 0 }

    var body: some View {
        Menu {
            Section(leftText) {
                Button("Refresh now", systemImage: "arrow.clockwise") { refresh() }
                    .disabled(exhausted || store.isRefreshing)
                Button("Live rates…", systemImage: "bolt") { showSettings = true }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, isActive: store.isRefreshing)
                .opacity(exhausted ? 0.35 : 1)
                .accessibilityLabel("Refresh rates")
                .accessibilityValue(leftText)
        } primaryAction: {
            refresh()
        }
        .sensoryFeedback(.success, trigger: successes)
    }

    private var leftText: String {
        let n = store.remainingToday
        return n == 1 ? "1 refresh left today" : "\(n) refreshes left today"
    }

    private func refresh() {
        guard !store.isRefreshing else { return }
        Task {
            await store.manualRefresh()
            if store.status == .idle { successes += 1 }
        }
    }
}

// MARK: - Live rates settings

struct LiveRatesSheet: View {
    let store: RatesStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The free sources update once a day. For hourly rates, add a free CurrencyBeacon API key.")
                    Link(destination: URL(string: "https://currencybeacon.com")!) {
                        Label("Sign up free at currencybeacon.com", systemImage: "arrow.up.right.square")
                    }
                }

                Section {
                    if store.hasKey {
                        Label("Key saved · live rates on", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    SecureField(store.hasKey ? "Replace API key" : "Paste API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(trimmedKey.isEmpty)
                    if store.hasKey {
                        Button("Remove key", role: .destructive) {
                            store.setKey(nil)
                        }
                    }
                } header: {
                    Text("CurrencyBeacon API key")
                } footer: {
                    Text("Your key is stored only in this iPhone's Keychain. It is never synced or sent anywhere except CurrencyBeacon.")
                }

                Section {
                    LabeledContent("Manual refreshes",
                                   value: "\(store.remainingToday) of \(RefreshBudget.dailyLimit) left today")
                } footer: {
                    Text("Rates also refresh automatically when you open the app, at most once an hour.")
                }
            }
            .navigationTitle("Live rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        store.setKey(trimmedKey)
        key = ""
        Task { await store.manualRefresh() }
    }
}

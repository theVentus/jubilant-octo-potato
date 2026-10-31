import SwiftUI
import UIKit

// MARK: - Status and refresh

struct StatusLine: View {
    let store: RatesStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).symbolEffect(.rotate, isActive: store.isRefreshing)
            Text(label)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var icon: String {
        if store.isRefreshing { return "arrow.triangle.2.circlepath" }
        return store.status == .offline ? "wifi.slash" : "checkmark.circle"
    }

    private var label: String {
        guard let d = store.rates.updated else { return "No rates yet" }
        let when = d.formatted(.relative(presentation: .named))
        return store.status == .offline ? "Offline · rates \(when)" : "Rates updated \(when)"
    }
}


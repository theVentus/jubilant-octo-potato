import SwiftUI
import UIKit

/// Layering rule (iOS 26): content sits on the backdrop; glass is reserved for the floating
/// control layer (selection lens, keypad dock, toolbar) so content visibly refracts through it.
struct ContentView: View {
    @Environment(RatesStore.self) private var store
    @AppStorage("list") private var listRaw = "INR,USD,EUR,AED,GBP"
    @AppStorage("active") private var active = "USD"
    @AppStorage("expr") private var exprRaw = "1"
    @State private var calc = Calc("1")
    @State private var keypadOpen = true
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var dockHeight: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var glass

    private var list: [String] { listRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
    /// `-slowmo YES` stretches animations so CI can capture morph frames.
    private var anim: Animation {
        .smooth(duration: 0.45 * (UserDefaults.standard.bool(forKey: "slowmo") ? 6 : 1), extraBounce: 0.12)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        StatusLine(store: store)
                        Spacer()
                        GlassGlyph(code: active)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 20)
                    .padding(.top, -32)
                    LazyVStack(spacing: 2) {
                        ForEach(list, id: \.self) { code in
                            CurrencyRow(code: code,
                                        isActive: code == active,
                                        amount: amountText(code),
                                        detail: detailText(code))
                                .anchorPreference(key: RowBounds.self, value: .bounds) { [code: $0] }
                                .contentShape(.rect(cornerRadius: 28))
                                .onTapGesture { select(code) }
                                .contextMenu {
                                    Button { UIPasteboard.general.string = amountText(code) } label: {
                                        Label("Copy amount", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) { remove(code) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .backgroundPreferenceValue(RowBounds.self) { rows in
                        GeometryReader { g in
                            if let a = rows[active] {
                                let r = g[a]
                                // Single glass lens that glides to the active row, behind its content.
                                Color.clear
                                    .glassEffect(.regular.interactive(),
                                                 in: .rect(cornerRadius: 28))
                                    .frame(width: r.width, height: r.height)
                                    .offset(x: r.minX, y: r.minY)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.hidden)
            .keypadUnderlay(height: dockHeight)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting && keypadOpen { keypadOpen = false }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                KeypadDock(open: $keypadOpen,
                           code: active,
                           display: amountText(active),
                           anim: anim,
                           ns: glass,
                           onHeight: { dockHeight = $0 }) { key in
                    withAnimation(.snappy(duration: 0.18)) { calc.press(key) }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .refreshable { await store.manualRefresh() }
            .background { Backdrop(activeCode: active) }
            .navigationTitle("Currency")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    RefreshButton(store: store, showSettings: $showSettings)
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showSettings) { LiveRatesSheet(store: store) }
            .sheet(isPresented: $showPicker) {
                CurrencyPicker(selected: list,
                               all: store.rates.rates.keys.sorted { Currency.name($0) < Currency.name($1) },
                               toggle: toggle,
                               move: { from, to in var l = list; l.move(fromOffsets: from, toOffset: to); setList(l) },
                               delete: { idx in idx.map { list[$0] }.forEach(remove) })
            }
        }
        .onAppear {
            calc = Calc(exprRaw)
            let d = UserDefaults.standard
            if d.bool(forKey: "showPicker") { showPicker = true }
            if d.bool(forKey: "showSettings") { showSettings = true }
            if d.bool(forKey: "demoExpand") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { keypadOpen = true }
            }
            if d.bool(forKey: "startCollapsed") { keypadOpen = false }
            if let c = d.string(forKey: "demoSelect") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { select(c) }
            }
            if d.bool(forKey: "demoCollapse") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { keypadOpen = false }
            }
        }
        .onChange(of: calc.text) { _, t in exprRaw = t }
        .task { await store.autoRefresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.autoRefresh() } }
        }
        .sensoryFeedback(.selection, trigger: calc.text)
        .sensoryFeedback(.impact(weight: .light), trigger: active)
    }

    private func amountText(_ code: String) -> String {
        if code == active { return Calc.pretty(calc.text) }
        guard let v = calc.value, let c = store.rates.convert(v, from: active, to: code) else { return "—" }
        return Fmt.amount(c)
    }

    private func detailText(_ code: String) -> String? {
        if code == active, calc.hasOperator, let v = calc.value { return "= " + Fmt.amount(v) }
        return nil
    }

    private func select(_ code: String) {
        guard code != active else {
            if !keypadOpen { keypadOpen = true }
            return
        }
        let v = calc.value.flatMap { store.rates.convert($0, from: active, to: code) } ?? 0
        withAnimation(anim) {
            active = code
            var c = Calc(Calc.plain((v * 100).rounded() / 100))
            c.justEvaluated = true
            calc = c
            keypadOpen = true
        }
    }

    private func setList(_ l: [String]) { listRaw = l.joined(separator: ",") }

    private func remove(_ code: String) {
        var l = list
        l.removeAll { $0 == code }
        guard !l.isEmpty else { return }
        setList(l)
        if active == code { select(l[0]) }
    }

    private func toggle(_ code: String) {
        if list.contains(code) { remove(code) } else { setList(list + [code]) }
    }
}

// MARK: - Content

struct RowBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}


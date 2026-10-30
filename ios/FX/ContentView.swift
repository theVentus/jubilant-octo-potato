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
                    .padding(.trailing, 16)
                    .padding(.top, -40)
                    LazyVStack(spacing: 4) {
                        ForEach(list, id: \.self) { code in
                            CurrencyRow(code: code,
                                        isActive: code == active,
                                        amount: amountText(code),
                                        detail: detailText(code))
                                .anchorPreference(key: RowBounds.self, value: .bounds) { [code: $0] }
                                .contentShape(.rect(cornerRadius: 30))
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
                                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                                                 in: .rect(cornerRadius: 30))
                                    .frame(width: r.width, height: r.height)
                                    .offset(x: r.minX, y: r.minY)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting && keypadOpen { withAnimation(anim) { keypadOpen = false } }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                KeypadDock(open: $keypadOpen,
                           code: active,
                           display: amountText(active),
                           anim: anim,
                           ns: glass) { key in
                    withAnimation(.snappy(duration: 0.18)) { calc.press(key) }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .refreshable { await store.refresh() }
            .background { Backdrop(activeCode: active) }
            .navigationTitle("Currency")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
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
            if d.bool(forKey: "startCollapsed") { keypadOpen = false }
            if let c = d.string(forKey: "demoSelect") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { select(c) }
            }
            if d.bool(forKey: "demoCollapse") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(anim) { keypadOpen = false } }
            }
        }
        .onChange(of: calc.text) { _, t in exprRaw = t }
        .task { await store.refresh() }
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
            if !keypadOpen { withAnimation(anim) { keypadOpen = true } }
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
        return store.lastRefreshFailed ? "wifi.slash" : "checkmark.circle"
    }

    private var label: String {
        guard let d = store.rates.updated else { return "No rates yet" }
        let when = d.formatted(.relative(presentation: .named))
        return store.lastRefreshFailed ? "Offline · rates \(when)" : "Rates updated \(when)"
    }
}

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

// MARK: - Backdrop

/// "ambient" (default): the active currency's flag as a blurred light source. "system": flat.
struct Backdrop: View {
    var activeCode: String
    @AppStorage("bg") private var style = "ambient"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color.black : Color(white: 0.96))
            if style != "system", let f = Currency.flag(activeCode) {
                ZStack {
                    Text(f)
                        .font(.system(size: 640))
                        .blur(radius: 80)
                        .opacity(dark ? 0.85 : 0.8)
                        .offset(y: -300)
                    Text(f)
                        .font(.system(size: 640))
                        .scaleEffect(x: -1)
                        .blur(radius: 110)
                        .opacity(dark ? 0.5 : 0.55)
                        .offset(y: 420)
                }
                .saturation(1.35)
                .id(activeCode)
                .transition(.opacity)
                LinearGradient(colors: dark ? [.black.opacity(0.15), .black.opacity(0.45)]
                                            : [.white.opacity(0.0), .white.opacity(0.2)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: activeCode)
        .ignoresSafeArea()
    }
}

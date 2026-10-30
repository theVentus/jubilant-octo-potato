import SwiftUI

struct ContentView: View {
    @Environment(RatesStore.self) private var store
    @AppStorage("list") private var listRaw = "INR,USD,EUR,AED,GBP"
    @AppStorage("active") private var active = "USD"
    @AppStorage("expr") private var exprRaw = "1"
    @State private var calc = Calc("1")
    @State private var showPicker = false
    @State private var editMode: EditMode = .inactive

    private var list: [String] { listRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    StatusPill(store: store)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 6, trailing: 20))

                    ForEach(list, id: \.self) { code in
                        CurrencyRow(code: code,
                                    isActive: code == active,
                                    amount: amountText(code),
                                    detail: detailText(code))
                            .contentShape(.rect(cornerRadius: 28))
                            .onTapGesture { select(code) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions {
                                Button(role: .destructive) { remove(code) } label: { Label("Remove", systemImage: "trash") }
                            }
                    }
                    .onMove { from, to in
                        var l = list; l.move(fromOffsets: from, toOffset: to); setList(l)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
                .refreshable { await store.refresh() }

                Keypad { key in
                    withAnimation(.snappy(duration: 0.18)) { calc.press(key) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .background { Backdrop(activeCode: active) }
            .navigationTitle("Currency")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showPicker) {
                CurrencyPicker(selected: list, all: store.rates.rates.keys.sorted { Currency.name($0) < Currency.name($1) }) { toggle($0) }
            }
        }
        .onAppear {
            calc = Calc(exprRaw)
            if UserDefaults.standard.bool(forKey: "showPicker") { showPicker = true }
        }
        .onChange(of: calc.text) { _, t in exprRaw = t }
        .task { await store.refresh() }
        .sensoryFeedback(.selection, trigger: calc.text)
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
        guard code != active else { return }
        let v = calc.value.flatMap { store.rates.convert($0, from: active, to: code) } ?? 0
        withAnimation(.snappy) {
            active = code
            var c = Calc(Calc.plain((v * 100).rounded() / 100))
            c.justEvaluated = true
            calc = c
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

// MARK: - Pieces

struct CurrencyRow: View {
    let code: String
    let isActive: Bool
    let amount: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: code, size: 46)
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
                        .font(.system(size: isActive ? 30 : 26, weight: isActive ? .semibold : .regular, design: .rounded))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(isActive ? .regular.tint(Color.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 28))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

struct FlagBadge: View {
    let code: String
    var size: CGFloat = 46

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
        .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

struct StatusPill: View {
    let store: RatesStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .symbolEffect(.rotate, isActive: store.isRefreshing)
            Text(label)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var icon: String {
        if store.isRefreshing { return "arrow.triangle.2.circlepath" }
        return store.lastRefreshFailed ? "wifi.slash" : "checkmark.circle"
    }

    private var label: String {
        guard let d = store.rates.updated else { return "No rates yet" }
        let when = d.formatted(.relative(presentation: .named))
        return store.lastRefreshFailed ? "Offline · rates \(when)" : "Updated \(when)"
    }
}

struct Keypad: View {
    let onKey: (Key) -> Void

    private let rows: [[Key]] = [
        [.clear, .percent, .back, .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .op("×")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−")],
        [.digit("1"), .digit("2"), .digit("3"), .op("+")],
        [.digit("00"), .digit("0"), .dot, .equals],
    ]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(rows[r], id: \.self) { k in
                            KeyButton(key: k) { onKey(k) }
                        }
                    }
                }
            }
        }
    }
}

struct KeyButton: View {
    let key: Key
    let action: () -> Void

    var body: some View {
        if key == .equals {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(.orange)
        } else {
            Button(action: action) { label.foregroundStyle(foreground) }
                .buttonStyle(.glass)
        }
    }

    private var foreground: Color {
        if key.isOperator { return .orange }
        if key.isFunction { return .secondary }
        return .primary
    }

    private var label: some View {
        Group {
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
        .font(.system(size: 26, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private static func symbol(_ o: Character) -> String {
        switch o { case "÷": "divide"; case "×": "multiply"; case "−": "minus"; default: "plus" }
    }
}

struct CurrencyPicker: View {
    let selected: [String]
    let all: [String]
    let toggle: (String) -> Void
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
                    Section("Selected") { ForEach(selected, id: \.self) { row($0) } }
                }
                Section(query.isEmpty ? "All currencies" : "Results") {
                    ForEach(filtered, id: \.self) { row($0) }
                }
            }
            .searchable(text: $query, prompt: "Search currency")
            .navigationTitle("Currencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                Image(systemName: selected.contains(code) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(code) ? Color.accentColor : Color.secondary.opacity(0.5))
            }
        }
        .tint(.primary)
    }
}

/// Background styles under evaluation: "system", "graphite", "ambient".
struct Backdrop: View {
    var activeCode: String
    @AppStorage("bg") private var style = "graphite"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            switch style {
            case "system":
                (scheme == .dark ? Color.black : Color(white: 0.94))
            case "ambient":
                (scheme == .dark ? Color.black : Color(white: 0.96))
                if let f = Currency.flag(activeCode) {
                    Text(f)
                        .font(.system(size: 520))
                        .blur(radius: 110)
                        .saturation(1.3)
                        .opacity(scheme == .dark ? 0.55 : 0.45)
                        .offset(y: -220)
                        .id(activeCode)
                        .transition(.opacity)
                }
            default: // graphite
                (scheme == .dark ? Color(white: 0.055) : Color(red: 0.93, green: 0.925, blue: 0.915))
                RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.55), .clear],
                               center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 620)
                Grain().opacity(scheme == .dark ? 0.06 : 0.05).blendMode(.overlay)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: activeCode)
        .ignoresSafeArea()
    }
}

/// Static fine noise, drawn once.
struct Grain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<Int(size.width * size.height / 9) {
                let x = Double.random(in: 0..<size.width, using: &rng)
                let y = Double.random(in: 0..<size.height, using: &rng)
                let w = Double.random(in: 0...1, using: &rng)
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color(white: w)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

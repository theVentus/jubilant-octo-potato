import Foundation
import Observation
import Security

/// USD-based rate table. `rates[X]` = units of X per 1 USD.
struct Rates: Codable, Equatable, Sendable {
    var base: String
    var updated: Date?
    var source: String?
    var rates: [String: Double]

    static let empty = Rates(base: "USD", updated: nil, source: nil, rates: [:])

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let f = rates[from], let t = rates[to], f > 0 else { return nil }
        return amount / f * t
    }

    static func decode(_ data: Data) throws -> Rates {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = iso(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return try d.decode(Rates.self, from: data)
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: s)
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    /// Keeps real ISO 4217 currencies (drops crypto, metals, junk), uppercases codes.
    static func cleaned(_ raw: [String: Double]) -> [String: Double] {
        let iso = Set(Locale.commonISOCurrencyCodes)
        var out: [String: Double] = [:]
        for (k, v) in raw {
            let c = k.uppercased()
            if iso.contains(c), v.isFinite, v > 0 { out[c] = v }
        }
        out["USD"] = 1
        return out
    }
}

// MARK: - Sources

/// Where rates come from. Keyless sources update once a day; CurrencyBeacon (free key) updates hourly.
enum RateSource {
    static let beacon = URL(string: "https://api.currencybeacon.com/v1/latest?base=USD")!
    static let fawaz = [
        URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json")!,
        URL(string: "https://latest.currency-api.pages.dev/v1/currencies/usd.json")!,
    ]
    static let erAPI = URL(string: "https://open.er-api.com/v6/latest/USD")!

    static func parseBeacon(_ data: Data) -> Rates? {
        struct R: Decodable {
            struct Meta: Decodable { let code: Int }
            struct Body: Decodable { let date: String?; let rates: [String: Double] }
            let meta: Meta?; let response: Body
        }
        guard let r = try? JSONDecoder().decode(R.self, from: data), (r.meta?.code ?? 200) == 200 else { return nil }
        let rates = Rates.cleaned(r.response.rates)
        guard rates.count > 20 else { return nil }
        return Rates(base: "USD", updated: r.response.date.flatMap(Rates.iso) ?? Date(), source: "CurrencyBeacon", rates: rates)
    }

    static func parseFawaz(_ data: Data) -> Rates? {
        struct R: Decodable { let date: String; let usd: [String: Double] }
        guard let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        let rates = Rates.cleaned(r.usd)
        guard rates.count > 20 else { return nil }
        return Rates(base: "USD", updated: Rates.iso(r.date), source: "Currency API", rates: rates)
    }

    static func parseERAPI(_ data: Data) -> Rates? {
        struct R: Decodable { let result: String; let time_last_update_unix: Double; let rates: [String: Double] }
        guard let r = try? JSONDecoder().decode(R.self, from: data), r.result == "success" else { return nil }
        return Rates(base: "USD", updated: Date(timeIntervalSince1970: r.time_last_update_unix),
                     source: "Exchange Rate API", rates: Rates.cleaned(r.rates))
    }
}

enum RatesLoader {
    static var cacheURL: URL { URL.documentsDirectory.appending(path: "rates.json") }

    static func loadInitial(bundle: Bundle = .main) -> Rates {
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? Rates.decode($0) }
        let bundled = bundle.url(forResource: "rates", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? Rates.decode($0) }
        return newest(cached, bundled) ?? .empty
    }

    static func newest(_ a: Rates?, _ b: Rates?) -> Rates? {
        let valid = [a, b].compactMap { $0 }.filter { !$0.rates.isEmpty }
        return valid.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    static func save(_ r: Rates) { try? r.encoded().write(to: cacheURL, options: .atomic) }

    enum Outcome { case ok(Rates), keyRejected, quotaExceeded, offline }

    /// Live source first when a key is set, then the keyless chain.
    static func fetch(key: String?) async -> Outcome {
        var keyProblem: Outcome?
        if let key, !key.isEmpty {
            var req = request(RateSource.beacon)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (data, status) = try? await send(req) {
                if status == 200, let r = RateSource.parseBeacon(data) { return .ok(r) }
                if status == 401 || status == 403 { keyProblem = .keyRejected }
                if status == 429 { keyProblem = .quotaExceeded }
            }
        }
        for url in RateSource.fawaz {
            if let (data, status) = try? await send(request(url)), status == 200, let r = RateSource.parseFawaz(data) {
                return keyProblem.map { _ in .ok(r) } ?? .ok(r)
            }
        }
        if let (data, status) = try? await send(request(RateSource.erAPI)), status == 200, let r = RateSource.parseERAPI(data) {
            return .ok(r)
        }
        return keyProblem ?? .offline
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return req
    }

    private static func send(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, res) = try await URLSession.shared.data(for: req)
        return (data, (res as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// MARK: - Refresh budget

/// Manual refreshes allowed per calendar day; protects the free CurrencyBeacon quota (5,000/month).
struct RefreshBudget: Equatable {
    static let dailyLimit = 30
    var day: String
    var used: Int

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func remaining(on d: Date) -> Int { day == Self.dayKey(d) ? max(0, Self.dailyLimit - used) : Self.dailyLimit }

    func spending(on d: Date) -> RefreshBudget {
        let k = Self.dayKey(d)
        return RefreshBudget(day: k, used: (day == k ? used : 0) + 1)
    }
}

// MARK: - Keychain (API key never leaves the phone)

enum KeyStore {
    private static let service = "com.theventus.fx.currencybeacon"

    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ key: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Store

@MainActor @Observable
final class RatesStore {
    enum Status: Equatable { case idle, refreshing, offline, keyRejected, quotaExceeded, limitReached }

    private(set) var rates: Rates
    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?
    private(set) var budget: RefreshBudget
    private(set) var hasKey: Bool

    var isRefreshing: Bool { status == .refreshing }
    var remainingToday: Int { budget.remaining(on: Date()) }
    var isLive: Bool { rates.source == "CurrencyBeacon" }

    init() {
        rates = RatesLoader.loadInitial()
        let d = UserDefaults.standard
        budget = RefreshBudget(day: d.string(forKey: "budgetDay") ?? "", used: d.integer(forKey: "budgetUsed"))
        lastChecked = d.object(forKey: "lastChecked") as? Date
        hasKey = KeyStore.read() != nil
    }

    func setKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        KeyStore.write(k)
        hasKey = !(k ?? "").isEmpty
    }

    /// Launch/foreground refresh: free of charge against the budget, at most once an hour.
    func autoRefresh() async {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 3600 { return }
        await run()
    }

    /// The "Refresh now" button.
    func manualRefresh() async {
        guard remainingToday > 0 else { status = .limitReached; return }
        budget = budget.spending(on: Date())
        UserDefaults.standard.set(budget.day, forKey: "budgetDay")
        UserDefaults.standard.set(budget.used, forKey: "budgetUsed")
        await run()
    }

    private func run() async {
        guard status != .refreshing else { return }
        status = .refreshing
        let outcome = await RatesLoader.fetch(key: KeyStore.read())
        lastChecked = Date()
        UserDefaults.standard.set(lastChecked, forKey: "lastChecked")
        switch outcome {
        case .ok(let r):
            if (r.updated ?? .distantPast) >= (rates.updated ?? .distantPast) || r.source == "CurrencyBeacon" {
                rates = r
                RatesLoader.save(r)
            }
            status = .idle
        case .keyRejected: status = .keyRejected
        case .quotaExceeded: status = .quotaExceeded
        case .offline: status = .offline
        }
    }
}

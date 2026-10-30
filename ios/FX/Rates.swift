import Foundation
import Observation

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
        return f.date(from: s)
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }
}

/// Offline order: newest of (on-device cache, bundled copy). Online: repo file, then the API directly.
enum RatesLoader {
    static let remote = URL(string: "https://raw.githubusercontent.com/theVentus/jubilant-octo-potato/main/rates.json")!
    static let fallback = URL(string: "https://open.er-api.com/v6/latest/USD")!
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

    static func fetch() async -> Rates? {
        if let r = try? await get(remote).flatMap({ try Rates.decode($0) }), !r.rates.isEmpty { return r }
        struct ERAPI: Decodable { let result: String; let time_last_update_unix: Double; let rates: [String: Double] }
        if let data = try? await get(fallback), let j = try? JSONDecoder().decode(ERAPI.self, from: data), j.result == "success" {
            return Rates(base: "USD", updated: Date(timeIntervalSince1970: j.time_last_update_unix),
                         source: "open.er-api.com", rates: j.rates)
        }
        return nil
    }

    private static func get(_ url: URL) async throws -> Data? {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, res) = try await URLSession.shared.data(for: req)
        return (res as? HTTPURLResponse)?.statusCode == 200 ? data : nil
    }
}

@MainActor @Observable
final class RatesStore {
    private(set) var rates: Rates
    private(set) var isRefreshing = false
    private(set) var lastRefreshFailed = false

    init() { rates = RatesLoader.loadInitial() }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let r = await RatesLoader.fetch() {
            if (r.updated ?? .distantPast) >= (rates.updated ?? .distantPast) {
                rates = r
                RatesLoader.save(r)
            }
            lastRefreshFailed = false
        } else {
            lastRefreshFailed = true
        }
    }
}

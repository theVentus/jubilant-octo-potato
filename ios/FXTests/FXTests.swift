import XCTest
@testable import FX

final class FXTests: XCTestCase {
    let r = Rates(base: "USD", updated: nil, source: nil, rates: ["USD": 1, "INR": 80, "EUR": 0.8])

    func testConvert() {
        XCTAssertEqual(r.convert(10, from: "USD", to: "INR")!, 800, accuracy: 1e-9)
        XCTAssertEqual(r.convert(800, from: "INR", to: "EUR")!, 8, accuracy: 1e-9)
        XCTAssertNil(r.convert(1, from: "USD", to: "XXX"))
    }

    func testPrecedence() {
        XCTAssertEqual(Calc.evaluate("2+3×4"), 14)
        XCTAssertEqual(Calc.evaluate("10÷4−1"), 1.5)
        XCTAssertEqual(Calc.evaluate("5+"), 5)
        XCTAssertEqual(Calc.evaluate("2."), 2)
        XCTAssertNil(Calc.evaluate("1÷0"))
    }

    func testInput() {
        var c = Calc("0")
        let keys: [Key] = [.digit("1"), .digit("2"), .op("+"), .op("×"), .digit("3"), .dot, .dot, .digit("5")]
        keys.forEach { c.press($0) }
        XCTAssertEqual(c.text, "12×3.5")
        c.press(.equals)
        XCTAssertEqual(c.text, "42")
        c.press(.digit("7"))
        XCTAssertEqual(c.text, "7")
        c.press(.back)
        XCTAssertEqual(c.text, "0")
        c.press(.digit("00"))
        XCTAssertEqual(c.text, "0")
        c.press(.digit("5")); c.press(.percent)
        XCTAssertEqual(c.text, "0.05")
    }

    func testDecodeDates() throws {
        let a = try Rates.decode(Data(#"{"base":"USD","updated":"2026-10-30T00:02:31.000Z","rates":{"USD":1}}"#.utf8))
        XCTAssertNotNil(a.updated)
        let b = try Rates.decode(Data(#"{"base":"USD","updated":null,"rates":{}}"#.utf8))
        XCTAssertNil(b.updated)
    }

    func testBundledRatesAvailableOffline() {
        let loaded = RatesLoader.loadInitial(bundle: .main)
        XCTAssertGreaterThan(loaded.rates.count, 100)
        XCTAssertNotNil(loaded.rates["INR"])
    }

    func testNewestWins() {
        let old = Rates(base: "USD", updated: Date(timeIntervalSince1970: 0), source: nil, rates: ["USD": 1])
        let new = Rates(base: "USD", updated: Date(), source: nil, rates: ["USD": 1])
        XCTAssertEqual(RatesLoader.newest(old, new), new)
        XCTAssertEqual(RatesLoader.newest(nil, old), old)
    }

    // MARK: - Source parsers

    /// 25 real ISO codes (lowercase) so parsers clear their ">20 rates" sanity check.
    private let sampleCodes = ["usd", "inr", "eur", "gbp", "jpy", "aud", "cad", "chf", "cny", "hkd",
                               "sgd", "aed", "sar", "omr", "qar", "kwd", "bhd", "nzd", "sek", "nok",
                               "dkk", "zar", "brl", "mxn", "thb"]

    private func sampleRates(uppercase: Bool) -> [String: Double] {
        var out: [String: Double] = [:]
        for (i, c) in sampleCodes.enumerated() { out[uppercase ? c.uppercased() : c] = Double(i + 1) }
        out[uppercase ? "USD" : "usd"] = 1
        out[uppercase ? "INR" : "inr"] = 88.5
        return out
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testParseBeacon() throws {
        let body: [String: Any] = [
            "meta": ["code": 200, "disclaimer": "Usage subject to terms"],
            "response": ["date": "2026-10-30T12:00:00Z", "base": "USD", "rates": sampleRates(uppercase: true)],
        ]
        let r = try XCTUnwrap(RateSource.parseBeacon(try json(body)))
        XCTAssertEqual(r.source, "CurrencyBeacon")
        XCTAssertEqual(r.base, "USD")
        XCTAssertEqual(r.rates["INR"], 88.5)
        XCTAssertEqual(r.rates["USD"], 1)
        XCTAssertEqual(r.updated, Date(timeIntervalSince1970: 1_793_318_400 + 12 * 3600))
    }

    func testParseBeaconRejectsErrorCode() throws {
        let body: [String: Any] = [
            "meta": ["code": 401, "error_type": "invalid_api_key"],
            "response": ["rates": sampleRates(uppercase: true)],
        ]
        XCTAssertNil(RateSource.parseBeacon(try json(body)))
        XCTAssertNil(RateSource.parseBeacon(Data("not json".utf8)))
    }

    func testParseFawaz() throws {
        var usd = sampleRates(uppercase: false)
        usd["btc"] = 0.0000094
        usd["doge"] = 5.2
        let r = try XCTUnwrap(RateSource.parseFawaz(try json(["date": "2026-10-30", "usd": usd])))
        XCTAssertEqual(r.source, "Currency API")
        XCTAssertEqual(r.rates["INR"], 88.5)
        XCTAssertNil(r.rates["inr"])
        XCTAssertNil(r.rates["BTC"])
        XCTAssertNil(r.rates["DOGE"])
        XCTAssertEqual(r.rates.count, sampleCodes.count)
        XCTAssertEqual(r.updated, Date(timeIntervalSince1970: 1_793_318_400)) // 2026-10-30T00:00:00Z
    }

    func testParseERAPI() throws {
        let ok: [String: Any] = ["result": "success", "time_last_update_unix": 1_793_318_400,
                                 "rates": sampleRates(uppercase: true)]
        let r = try XCTUnwrap(RateSource.parseERAPI(try json(ok)))
        XCTAssertEqual(r.source, "Exchange Rate API")
        XCTAssertEqual(r.rates["INR"], 88.5)
        XCTAssertEqual(r.updated, Date(timeIntervalSince1970: 1_793_318_400))

        let bad: [String: Any] = ["result": "error", "time_last_update_unix": 0, "rates": [String: Double]()]
        XCTAssertNil(RateSource.parseERAPI(try json(bad)))
    }

    func testCleaned() {
        let c = Rates.cleaned(["inr": 88, "Eur": 0.9, "btc": 0.00001, "zzz": 3, "gbp": 0,
                               "jpy": -1, "chf": .infinity, "aud": .nan])
        XCTAssertEqual(c["INR"], 88)
        XCTAssertEqual(c["EUR"], 0.9)
        XCTAssertEqual(c["USD"], 1)  // always pinned
        XCTAssertEqual(Set(c.keys), ["INR", "EUR", "USD"])
        XCTAssertEqual(Rates.cleaned(["usd": 2])["USD"], 1)
    }

    // MARK: - Refresh budget

    func testRefreshBudgetDailyLimitAndReset() throws {
        let cal = Calendar.current
        let today = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)))
        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today))

        var b = RefreshBudget(day: "", used: 0)
        XCTAssertEqual(RefreshBudget.dailyLimit, 30)
        XCTAssertEqual(b.remaining(on: today), 30)
        b = b.spending(on: today)
        XCTAssertEqual(b.remaining(on: today), 29)
        for _ in 1..<30 { b = b.spending(on: today) }
        XCTAssertEqual(b.used, 30)
        XCTAssertEqual(b.remaining(on: today), 0)
        b = b.spending(on: today)
        XCTAssertEqual(b.remaining(on: today), 0) // never negative

        XCTAssertEqual(b.remaining(on: tomorrow), 30)
        let next = b.spending(on: tomorrow)
        XCTAssertEqual(next.used, 1)
        XCTAssertEqual(next.remaining(on: tomorrow), 29)
    }

    // MARK: - Status text

    func testFreshness() {
        let now = Date(timeIntervalSince1970: 1_793_318_400)
        XCTAssertEqual(Freshness.ago(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(Freshness.ago(now.addingTimeInterval(-14 * 60), now: now), "14 min ago")
        XCTAssertEqual(Freshness.ago(now.addingTimeInterval(-9 * 3600 - 120), now: now), "9 h ago")
        XCTAssertEqual(Freshness.ago(now.addingTimeInterval(-3 * 86400), now: now), "3 d ago")
        XCTAssertEqual(Freshness.ago(now.addingTimeInterval(60), now: now), "just now")
        XCTAssertEqual(Freshness.sourceLabel("CurrencyBeacon"), "Live")
        XCTAssertEqual(Freshness.sourceLabel("Currency API"), "Daily rates")
        XCTAssertEqual(Freshness.sourceLabel(nil), "Daily rates")
    }
}

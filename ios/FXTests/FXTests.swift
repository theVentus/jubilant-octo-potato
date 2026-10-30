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
}

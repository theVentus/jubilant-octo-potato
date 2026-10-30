import Foundation

enum Currency {
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    private static let regionOverride: [String: String] = [
        "EUR": "EU", "ANG": "CW", "XCD": "AG", "XAF": "CM", "XOF": "SN", "XPF": "PF", "XCG": "CW",
    ]

    /// Flag emoji for the issuing region; nil for supranational/special codes.
    static func flag(_ code: String) -> String? {
        let region: String
        if let r = regionOverride[code] { region = r }
        else if code.hasPrefix("X") { return nil }
        else { region = String(code.prefix(2)) }
        let scalars = region.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    static func symbol(_ code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        let s = f.currencySymbol ?? code
        return s.count > 3 ? "" : s
    }
}

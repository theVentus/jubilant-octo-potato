import Foundation

enum Key: Hashable {
    case digit(String)   // "0"..."9", "00"
    case dot, op(Character), back, clear, equals, percent

    var isOperator: Bool { if case .op = self { return true }; return false }
    var isFunction: Bool {
        switch self { case .clear, .back, .percent: return true; default: return false }
    }
}

/// Calculator input for the active row: "12.5+3×2", evaluated with × ÷ before + −.
struct Calc: Equatable {
    var text: String
    var justEvaluated = false

    static let ops: Set<Character> = ["+", "−", "×", "÷"]

    init(_ text: String = "0") { self.text = text.isEmpty ? "0" : text }

    var endsWithOp: Bool { text.last.map { Self.ops.contains($0) } ?? false }
    var hasOperator: Bool { text.dropFirst().contains { Self.ops.contains($0) } }
    var currentNumber: Substring {
        text.split(omittingEmptySubsequences: false, whereSeparator: { Self.ops.contains($0) }).last ?? ""
    }
    var value: Double? { Self.evaluate(text) }

    mutating func press(_ key: Key) {
        switch key {
        case .digit(let d):
            if justEvaluated { text = "0"; justEvaluated = false }
            let cur = currentNumber
            if cur.filter(\.isNumber).count >= 12 { return }
            if cur == "0" || cur == "-0" {
                text.removeLast()
                text += d == "00" ? "0" : d
            } else if cur.isEmpty && d == "00" {
                text += "0"
            } else {
                text += d
            }
        case .dot:
            if justEvaluated { text = "0"; justEvaluated = false }
            let cur = currentNumber
            if cur.contains(".") { return }
            text += cur.isEmpty ? "0." : "."
        case .op(let o):
            justEvaluated = false
            if endsWithOp || text.last == "." { text.removeLast() }
            text.append(o)
        case .back:
            justEvaluated = false
            text.removeLast()
            if text.isEmpty || text == "-" { text = "0" }
        case .clear:
            text = "0"; justEvaluated = false
        case .equals:
            guard hasOperator, let v = value else { return }
            text = Self.plain(v); justEvaluated = true
        case .percent:
            let cur = currentNumber
            guard !cur.isEmpty, let n = Double(cur) else { return }
            text.removeLast(cur.count)
            text += Self.plain(n / 100)
        }
    }

    static func evaluate(_ s: String) -> Double? {
        var nums: [Double] = []
        var ops: [Character] = []
        var buf = ""
        func number(_ b: String) -> Double? { Double(b.hasSuffix(".") ? String(b.dropLast()) : b) }
        for ch in s {
            if Self.ops.contains(ch) && !buf.isEmpty {
                guard let n = number(buf) else { return nil }
                nums.append(n); ops.append(ch); buf = ""
            } else {
                buf.append(ch)
            }
        }
        if !buf.isEmpty {
            guard let n = number(buf) else { return nil }
            nums.append(n)
        } else if !ops.isEmpty {
            ops.removeLast()
        }
        guard !nums.isEmpty, nums.count == ops.count + 1 else { return nil }

        var terms = [nums[0]]
        var addOps: [Character] = []
        for (i, o) in ops.enumerated() {
            let r = nums[i + 1]
            switch o {
            case "×": terms[terms.count - 1] *= r
            case "÷":
                guard r != 0 else { return nil }
                terms[terms.count - 1] /= r
            default: terms.append(r); addOps.append(o)
            }
        }
        var result = terms[0]
        for (i, o) in addOps.enumerated() { result = o == "+" ? result + terms[i + 1] : result - terms[i + 1] }
        return result.isFinite ? result : nil
    }

    private static let plainFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 6
        return f
    }()

    static func plain(_ v: Double) -> String { plainFormatter.string(from: v as NSNumber) ?? "0" }

    /// Display form: grouped numbers, spaced operators, locale decimal separator.
    static func pretty(_ s: String) -> String {
        var out = ""
        var buf = ""
        for ch in s {
            if ops.contains(ch) && !buf.isEmpty { out += Fmt.groupTyped(buf) + " \(ch) "; buf = "" }
            else { buf.append(ch) }
        }
        return out + Fmt.groupTyped(buf)
    }
}

enum Fmt {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    static func amount(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let a = abs(v)
        f.maximumFractionDigits = a == 0 ? 0 : a < 1 ? 4 : 2
        return f.string(from: v as NSNumber) ?? "—"
    }

    /// Groups a number the user is still typing without losing a trailing "." or typed zeros.
    static func groupTyped(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let neg = parts[0].hasPrefix("-")
        let digits = parts[0].drop(while: { $0 == "-" })
        var r = grouped.string(from: NSNumber(value: Double(digits) ?? 0)) ?? String(digits)
        if neg { r = "-" + r }
        if parts.count > 1 { r += (grouped.decimalSeparator ?? ".") + parts[1] }
        return r
    }
}

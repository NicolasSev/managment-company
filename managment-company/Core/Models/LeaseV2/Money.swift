import Foundation

/// Lease v2 money: int64 minor units (1/100 of the major unit) plus an ISO-4217 currency.
///
/// The wire format (lease-v2 spec §0) is a JSON number with at most 2 decimals in major
/// units, so `350000` is `Money(minor: 35_000_000, currency: "KZT")`. All arithmetic stays in
/// integers; `Double` is used only at the formatting edge.
nonisolated struct Money: Hashable, Comparable {
    let minor: Int64
    let currency: String

    init(minor: Int64, currency: String) {
        self.minor = minor
        self.currency = currency
    }

    /// Builds money from a major-unit decimal, rounding half-up to 0.01 (spec §0).
    init(major: Decimal, currency: String) {
        self.init(minor: Money.minorUnits(from: major), currency: currency)
    }

    static func zero(_ currency: String) -> Money {
        Money(minor: 0, currency: currency)
    }

    var major: Decimal {
        Decimal(minor) / 100
    }

    var isZero: Bool { minor == 0 }
    var isPositive: Bool { minor > 0 }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.minor < rhs.minor
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        Money(minor: lhs.minor + rhs.minor, currency: lhs.currency)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        Money(minor: lhs.minor - rhs.minor, currency: lhs.currency)
    }

    /// Clamps negative amounts to zero.
    var nonNegative: Money {
        Money(minor: max(0, minor), currency: currency)
    }

    /// Shared app formatter (`AppFormatting.currency`), whole units.
    @MainActor
    func formatted() -> String {
        AppFormatting.currency(NSDecimalNumber(decimal: major).doubleValue, currency: currency)
    }

    /// Plain editable text (`"380000"`, `"1500.5"`) for text fields.
    var editableText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: major)) ?? "\(major)"
    }

    /// Half-up rounding of `value * 100` (spec §0).
    static func minorUnits(from value: Decimal) -> Int64 {
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Parses user input (`"380 000"`, `"1500,50"`) into money. `nil` for empty, non-numeric,
    /// or more than 2 decimals.
    static func parse(_ text: String, currency: String) -> Money? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let money = Money(major: decimal, currency: currency)
        // Reject precision loss: `1.005` must not silently become `1.01`.
        guard money.major == decimal else { return nil }
        return money
    }
}

extension KeyedDecodingContainer {
    /// Decodes a lease-v2 wire amount (a JSON number in major units) in the given currency.
    func decodeMoney(_ key: Key, currency: String) throws -> Money {
        Money(major: try decode(Decimal.self, forKey: key), currency: currency)
    }

    func decodeMoneyIfPresent(_ key: Key, currency: String) throws -> Money? {
        guard let value = try decodeIfPresent(Decimal.self, forKey: key) else { return nil }
        return Money(major: value, currency: currency)
    }
}

extension KeyedEncodingContainer {
    mutating func encodeMoney(_ money: Money, forKey key: Key) throws {
        try encode(money.major, forKey: key)
    }

    mutating func encodeMoneyIfPresent(_ money: Money?, forKey key: Key) throws {
        guard let money else { return }
        try encode(money.major, forKey: key)
    }
}

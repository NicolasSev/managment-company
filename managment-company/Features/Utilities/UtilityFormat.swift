import Foundation
import SwiftUI

/// Russian formats of the utility screens: a month as «Март 2026», a day as «22.11.2025», money with
/// kopecks only when there are some (`12 057,50 ₸`). Output only; input parsing is `parseDecimal`
/// and `Money.parse`.
enum UtilityFormat {
    private static let monthNames = [
        "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
        "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь",
    ]
    private static let monthShortNames = [
        "Янв", "Фев", "Мар", "Апр", "Май", "Июн", "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек",
    ]

    /// `(year, month)` of `YYYY-MM` (a `YYYY-MM-DD` day is accepted too).
    static func components(ofPeriod period: String) -> (year: Int, month: Int)? {
        let parts = period.prefix(7).split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return (year, month)
    }

    /// «Март 2026».
    static func periodTitle(_ period: String) -> String {
        guard let c = components(ofPeriod: period) else { return period }
        return "\(monthNames[c.month - 1]) \(c.year)"
    }

    /// «Март» (a cell of the grid).
    static func monthName(_ period: String) -> String {
        guard let c = components(ofPeriod: period) else { return period }
        return monthNames[c.month - 1]
    }

    /// «Мар».
    static func monthShort(_ period: String) -> String {
        guard let c = components(ofPeriod: period) else { return period }
        return monthShortNames[c.month - 1]
    }

    /// A year as digits only: `Text("\(2024)")` groups it as «2 024» in a Russian locale.
    static func year(_ value: Int) -> String {
        String(value)
    }

    static func periodKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// `YYYY-MM-DD` → «22.11.2025»; anything else comes back unchanged.
    static func day(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return value }
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return value }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// `12 057,50 ₸`; whole amounts have no kopecks. `nil` money is «—».
    static func money(_ amount: Decimal?, currency: String?, alwaysFraction: Bool = false) -> String {
        guard let amount else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = AppFormatting.displayLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.roundingMode = .halfUp
        let hasFraction = (amount * 100).isWhole && !amount.isWhole
        formatter.minimumFractionDigits = (alwaysFraction || hasFraction) ? 2 : 0
        formatter.maximumFractionDigits = (alwaysFraction || hasFraction) ? 2 : 0
        let number = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
        guard let currency, !currency.isEmpty else { return number }
        return "\(number)\u{00A0}\(AppFormatting.currencySymbol(for: currency))"
    }

    /// `93 %`.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))\u{00A0}%"
    }

    /// `+9,1 %`, `−9,1 %`; `nil` has no base to compare with.
    static func deltaPercent(_ value: Double?) -> String? {
        guard let value else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = AppFormatting.displayLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let text = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
        return "\(sign)\(text)\u{00A0}%"
    }

    /// Input like `1 092,68` or `8.5` as a decimal; `nil` for empty or non-numeric text.
    static func parseDecimal(_ text: String, maxFractionDigits: Int = 4) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var scaled = value * pow(10, maxFractionDigits)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded == scaled ? value : nil
    }

    /// Editable text of a decimal (`1092.68`, `128.55`).
    static func editableText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// `YYYY-MM-DD` of `date` in the owner's time zone.
    static func dayKey(_ date: Date, timeZoneIdentifier: String? = nil) -> String {
        AppFormatting.dayKey(for: date, timeZoneIdentifier: timeZoneIdentifier ?? "Asia/Almaty")
    }

    /// `YYYY-MM-DD` of a day the owner picked on the device (the picker works in the device calendar).
    static func localDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func date(fromDay day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(day.prefix(10)))
    }
}

extension Decimal {
    fileprivate var isWhole: Bool {
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded == self
    }
}

extension UtilityBillStatus {
    /// Tone of a status chip: colour plus the symbol of `StatusTone`, so it never rests on colour alone.
    var tone: StatusTone {
        switch self {
        case .expected: return .neutral
        case .missing: return .danger
        case .uploaded: return .info
        case .needsReview: return .warning
        case .confirmed: return .info
        case .paid: return .success
        case .unknown: return .neutral
        }
    }
}

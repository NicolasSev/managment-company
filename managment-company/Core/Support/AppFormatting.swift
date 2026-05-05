import Foundation

enum AppFormatting {
    static func currency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0

        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }

    static func compactAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return "\(formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") \(currency)"
    }

    static func parsedDate(from value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }

    static func dateString(
        from value: String?,
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style? = nil
    ) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let parsedDate = parsedDate(from: value) else { return value }

        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle ?? (value.contains("T") ? .short : .none)
        return formatter.string(from: parsedDate)
    }
}

import Foundation

/// Calendar-day helpers for lease v2. Wire dates are `YYYY-MM-DD` strings with no time zone;
/// they are handled on a fixed UTC Gregorian calendar so arithmetic never shifts a day.
enum LeaseDay {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ day: String) -> Date? {
        formatter.date(from: String(day.prefix(10)))
    }

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// Day key of a picker `Date` in the device time zone (what the user saw on the picker).
    static func string(fromPicker date: Date) -> String {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", local.year ?? 1970, local.month ?? 1, local.day ?? 1)
    }

    /// Picker `Date` (local midnight) for a wire day.
    static func pickerDate(_ day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// `to - from` in whole days.
    static func days(from: String, to: String) -> Int? {
        guard let a = date(from), let b = date(to) else { return nil }
        return calendar.dateComponents([.day], from: a, to: b).day
    }

    static func addingDays(_ days: Int, to day: String) -> String? {
        guard let d = date(day), let result = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return string(result)
    }

    /// `day` is on or before `other` (lexicographic compare is correct for ISO days).
    static func isOnOrBefore(_ day: String, _ other: String) -> Bool {
        String(day.prefix(10)) <= String(other.prefix(10))
    }

    /// Spec §3.3: the `due_day`-th of the month of `periodStart`, or the last day of that
    /// month if it is shorter.
    static func dueDate(periodStart: String, dueDay: Int) -> String {
        guard let start = date(periodStart) else { return periodStart }
        let comps = calendar.dateComponents([.year, .month], from: start)
        guard let firstOfMonth = calendar.date(from: comps),
              let lastDay = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else {
            return periodStart
        }
        let day = min(max(dueDay, 1), lastDay)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, day)
    }

    /// Short Russian form for rows, e.g. `15 мар. 2026`.
    static func display(_ day: String?) -> String {
        guard let day, !day.isEmpty else { return "-" }
        return AppFormatting.dateString(from: day) ?? day
    }
}

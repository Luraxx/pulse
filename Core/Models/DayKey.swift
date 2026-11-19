import Foundation

/// Helpers for calendar-day keys in the format "yyyy-MM-dd" (local time zone).
public enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Returns local midnight of the day.
    public static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    public static func today() -> String {
        string(from: Date())
    }

    public static func addDays(_ key: String, _ n: Int) -> String {
        guard let date = date(from: key),
              let shifted = Calendar.current.date(byAdding: .day, value: n, to: date) else {
            return key
        }
        return string(from: shifted)
    }

    /// All days from `from` to `to` (inclusive), chronological.
    public static func keys(from: String, to: String) -> [String] {
        guard var current = date(from: from), let endDate = date(from: to), current <= endDate else {
            return []
        }
        var result: [String] = []
        let calendar = Calendar.current
        while current <= endDate {
            result.append(string(from: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    /// Assigns an overnight measurement time to the wake-up day:
    /// samples between 18:00 and midnight count toward the next day.
    public static func nightKey(for sampleTime: Date) -> String {
        string(from: sampleTime.addingTimeInterval(6 * 3600))
    }

    /// Number of days between two keys (b - a).
    public static func distance(from a: String, to b: String) -> Int? {
        guard let da = date(from: a), let db = date(from: b) else { return nil }
        return Calendar.current.dateComponents([.day], from: da, to: db).day
    }
}

import Foundation

/// Tolerant extraction from Google Health API JSON objects.
/// The API is new (v4, May 2026) and some field names are not fully
/// documented — so it searches candidate keys in priority order
/// instead of decoding strictly.
public enum JSONExtract {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func date(from any: Any?) -> Date? {
        guard let string = any as? String else { return nil }
        if let date = isoPlain.date(from: string) ?? isoWithFraction.date(from: string) {
            return date
        }
        // Plain date "yyyy-MM-dd"
        if string.count == 10 {
            return DayKey.date(from: string)
        }
        return nil
    }

    public static func double(from any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Google CivilDate objects ({year, month, day}) or strings → "yyyy-MM-dd".
    public static func civilDateString(from any: Any?) -> String? {
        if let s = any as? String, s.count >= 10 {
            return String(s.prefix(10))
        }
        if let dict = any as? [String: Any],
           let year = double(from: dict["year"]),
           let month = double(from: dict["month"]),
           let day = double(from: dict["day"]) {
            return String(format: "%04d-%02d-%02d", Int(year), Int(month), Int(day))
        }
        return nil
    }

    /// Finds the first key from `keys` (priority order) via
    /// breadth-first search up to depth 4 and returns the Double value.
    public static func firstDouble(in object: Any, keys: [String]) -> Double? {
        for key in keys {
            if let value = search(object, key: key, depth: 4), let d = double(from: value) {
                return d
            }
        }
        return nil
    }

    public static func firstString(in object: Any, keys: [String]) -> String? {
        for key in keys {
            if let value = search(object, key: key, depth: 4) {
                if let s = value as? String { return s }
                if let civil = civilDateString(from: value) { return civil }
            }
        }
        return nil
    }

    public static func firstDate(in object: Any, keys: [String]) -> Date? {
        for key in keys {
            if let value = search(object, key: key, depth: 4), let d = date(from: value) {
                return d
            }
        }
        return nil
    }

    /// Breadth-first search for a key in nested dictionaries/arrays.
    private static func search(_ object: Any, key: String, depth: Int) -> Any? {
        var queue: [(Any, Int)] = [(object, 0)]
        while !queue.isEmpty {
            let (current, level) = queue.removeFirst()
            if level > depth { continue }
            if let dict = current as? [String: Any] {
                if let hit = dict[key] {
                    return hit
                }
                for value in dict.values {
                    queue.append((value, level + 1))
                }
            } else if let array = current as? [Any] {
                for value in array.prefix(20) {
                    queue.append((value, level + 1))
                }
            }
        }
        return nil
    }

    /// camelCase → snake_case ("heartRateVariability" → "heart_rate_variability").
    public static func snakeCase(_ camel: String) -> String {
        var result = ""
        for character in camel {
            if character.isUppercase {
                result.append("_")
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return result
    }
}

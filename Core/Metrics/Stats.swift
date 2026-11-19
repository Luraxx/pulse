import Foundation

/// Rolling baseline (mean ± standard deviation) of a metric.
public struct Baseline: Sendable {
    public let mean: Double
    public let sd: Double
    public let count: Int

    public init(mean: Double, sd: Double, count: Int) {
        self.mean = mean
        self.sd = sd
        self.count = count
    }

    /// From 5 data points the baseline counts as solid.
    public var isReliable: Bool { count >= 5 }

    public func z(_ value: Double, minSD: Double = 0.0001) -> Double {
        (value - mean) / max(sd, minSD)
    }
}

public enum Stats {
    public static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return sqrt(variance)
    }

    /// Percentile with linear interpolation, p in 0...1.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = clamp(p, 0, 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    /// Baseline from a list of values; nil with fewer than 3 points.
    public static func baseline(_ values: [Double]) -> Baseline? {
        guard values.count >= 3 else { return nil }
        return Baseline(mean: mean(values), sd: standardDeviation(values), count: values.count)
    }

    public static func logistic(_ x: Double) -> Double {
        1 / (1 + exp(-x))
    }

    public static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

/// Aggregations for trend views: long periods only become readable
/// through smoothing/weekly means (90 daily bars are just noise).
public enum TrendMath {
    /// Moving average over the last `window` calendar days
    /// (missing days are skipped, not counted as 0).
    public static func movingAverage(
        _ pairs: [(key: String, value: Double)],
        window: Int
    ) -> [(key: String, value: Double)] {
        guard window > 1 else { return pairs }
        let byKey = Dictionary(pairs.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        return pairs.map { point in
            let start = DayKey.addDays(point.key, -(window - 1))
            let values = DayKey.keys(from: start, to: point.key).compactMap { byKey[$0] }
            return (point.key, Stats.mean(values))
        }
    }

    /// Mean per calendar week; key = Monday of that week.
    public static func weeklyMean(
        _ pairs: [(key: String, value: Double)]
    ) -> [(key: String, value: Double)] {
        var buckets: [String: [Double]] = [:]
        for point in pairs {
            guard let date = DayKey.date(from: point.key) else { continue }
            let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sun
            let daysSinceMonday = (weekday + 5) % 7
            let monday = DayKey.addDays(point.key, -daysSinceMonday)
            buckets[monday, default: []].append(point.value)
        }
        return buckets.keys.sorted().map { ($0, Stats.mean(buckets[$0]!)) }
    }
}

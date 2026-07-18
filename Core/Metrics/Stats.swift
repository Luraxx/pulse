import Foundation

/// Rollierende Baseline (Mittelwert ± Standardabweichung) einer Metrik.
public struct Baseline: Sendable {
    public let mean: Double
    public let sd: Double
    public let count: Int

    public init(mean: Double, sd: Double, count: Int) {
        self.mean = mean
        self.sd = sd
        self.count = count
    }

    /// Ab 5 Datenpunkten gilt die Baseline als belastbar.
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

    /// Perzentil mit linearer Interpolation, p in 0...1.
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

    /// Baseline aus einer Werteliste; nil bei weniger als 3 Punkten.
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

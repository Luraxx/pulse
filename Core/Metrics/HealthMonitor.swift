import Foundation

public enum BandState: String, Sendable {
    case inRange
    case above
    case below
    case noData
    case calibrating
}

public enum HealthMetricKind: String, CaseIterable, Sendable {
    case restingHR
    case hrv
    case respiratoryRate
    case spo2
    case bodyTemp

    public var label: String {
        switch self {
        case .restingHR: return "Ruhepuls"
        case .hrv: return "HRV"
        case .respiratoryRate: return "Atemfrequenz"
        case .spo2: return "SpO₂"
        case .bodyTemp: return "Hauttemperatur"
        }
    }

    public var unit: String {
        switch self {
        case .restingHR: return "S/min"
        case .hrv: return "ms"
        case .respiratoryRate: return "/min"
        case .spo2: return "%"
        case .bodyTemp: return "°C"
        }
    }

    public func formatted(_ value: Double) -> String {
        switch self {
        case .restingHR, .hrv: return String(format: "%.0f", value)
        case .respiratoryRate, .spo2: return String(format: "%.1f", value)
        case .bodyTemp: return String(format: "%.2f", value)
        }
    }

    /// Minimum half bandwidth so narrow baselines don't become oversensitive.
    var minimumHalfWidth: Double {
        switch self {
        case .restingHR: return 3
        case .hrv: return 10
        case .respiratoryRate: return 0.8
        case .spo2: return 1.5
        case .bodyTemp: return 0.4
        }
    }
}

public struct HealthMetricStatus: Sendable {
    public let kind: HealthMetricKind
    public let value: Double?
    public let baseline: Baseline?
    public let lowerBound: Double?
    public let upperBound: Double?
    public let state: BandState
}

/// Whoop-like Health Monitor: each overnight metric is checked against the personal
/// baseline band (mean ± 1.65 SD).
public enum HealthMonitor {
    public static func evaluate(today: DayRecord, history: [DayRecord]) -> [HealthMetricStatus] {
        HealthMetricKind.allCases.map { kind in
            let value = value(kind, today)
            let values = history.compactMap { self.value(kind, $0) }.suffix(30)
            let baseline = Stats.baseline(Array(values))

            guard let value else {
                return HealthMetricStatus(kind: kind, value: nil, baseline: baseline, lowerBound: nil, upperBound: nil, state: .noData)
            }
            guard let baseline, baseline.isReliable else {
                return HealthMetricStatus(kind: kind, value: value, baseline: baseline, lowerBound: nil, upperBound: nil, state: .calibrating)
            }

            let halfWidth = max(1.65 * baseline.sd, kind.minimumHalfWidth)
            var lower: Double? = baseline.mean - halfWidth
            var upper: Double? = baseline.mean + halfWidth

            // SpO₂: only critical downward, hard lower limit 90 %.
            if kind == .spo2 {
                lower = max(90, baseline.mean - halfWidth)
                upper = nil
            }

            let state: BandState
            if let lower, value < lower {
                state = .below
            } else if let upper, value > upper {
                state = .above
            } else {
                state = .inRange
            }

            return HealthMetricStatus(
                kind: kind,
                value: value,
                baseline: baseline,
                lowerBound: lower,
                upperBound: upper,
                state: state
            )
        }
    }

    private static func value(_ kind: HealthMetricKind, _ record: DayRecord) -> Double? {
        switch kind {
        case .restingHR: return record.restingHR
        case .hrv: return record.hrvRmssd
        case .respiratoryRate: return record.respiratoryRate
        case .spo2: return record.spo2Avg
        case .bodyTemp: return record.bodyTemp
        }
    }

    // MARK: - Warning

    /// Is the deviation in the "bad" direction (sign of infection/
    /// overtraining)? HRV & SpO₂ are critical downward, the rest upward.
    public static func isConcerning(_ status: HealthMetricStatus) -> Bool {
        switch status.kind {
        case .hrv, .spo2: return status.state == .below
        case .restingHR, .respiratoryRate, .bodyTemp: return status.state == .above
        }
    }

    static func directionWord(_ kind: HealthMetricKind) -> String {
        switch kind {
        case .hrv, .spo2: return "niedrig"
        case .restingHR, .respiratoryRate, .bodyTemp: return "erhöht"
        }
    }
}

public struct HealthAlert: Sendable {
    public let kinds: [HealthMetricKind]
    public let message: String
    /// true = clear warning, false = mild notice.
    public let isWarning: Bool
}

extension HealthMonitor {
    /// Proactive warning from the last few days. Triggers when **several**
    /// metrics are off today OR **one** metric for ≥2 days — both
    /// classic early signs of infection or overtraining.
    public static func alert(records: [DayRecord], lookback: Int = 3) -> HealthAlert? {
        // Enough history for solid baselines is required.
        guard records.count >= 6 else { return nil }
        let n = records.count

        // Off metrics per day (last lookback+1 days).
        var dailyConcerning: [Set<HealthMetricKind>] = []
        let start = max(1, n - (lookback + 1))
        for i in start..<n {
            let statuses = evaluate(today: records[i], history: Array(records[0..<i]))
            dailyConcerning.append(Set(statuses.filter(isConcerning).map(\.kind)))
        }
        guard let today = dailyConcerning.last, !today.isEmpty else { return nil }

        // Rule 1: several metrics outside the baseline today.
        if today.count >= 2 {
            let names = today.map(\.label).sorted().joined(separator: ", ")
            return HealthAlert(
                kinds: Array(today),
                message: "\(today.count) Werte außerhalb deiner Baseline (\(names)) – möglicher Infekt oder Übertraining. Nimm es heute ruhiger.",
                isWarning: true
            )
        }

        // Rule 2: one metric continuously off for ≥2 days.
        var streaked: [(kind: HealthMetricKind, days: Int)] = []
        for kind in today {
            var streak = 0
            for set in dailyConcerning.reversed() {
                if set.contains(kind) { streak += 1 } else { break }
            }
            if streak >= 2 { streaked.append((kind, streak)) }
        }
        if let worst = streaked.max(by: { $0.days < $1.days }) {
            return HealthAlert(
                kinds: [worst.kind],
                message: "\(worst.kind.label) seit \(worst.days) Tagen \(directionWord(worst.kind)) – achte auf Erholung.",
                isWarning: true
            )
        }

        return nil
    }
}

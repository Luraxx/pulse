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

    /// Minimale halbe Bandbreite, damit enge Baselines nicht überempfindlich werden.
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

/// Whoop-artiger Health Monitor: Jede Nacht-Metrik wird gegen das persönliche
/// Baseline-Band (Mittelwert ± 1,65 SD) geprüft.
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

            // SpO₂: nur nach unten kritisch, harte Untergrenze 90 %.
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
}

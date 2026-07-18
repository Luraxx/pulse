import Foundation

public enum RecoveryZone: String, Sendable {
    case green, yellow, red
}

public struct RecoveryComponent: Sendable {
    public let key: String
    public let label: String
    /// Teil-Score 0–1.
    public let score01: Double
    /// Normalisiertes Gewicht (Summe aller Komponenten = 1).
    public let weight: Double
    public let detail: String
}

public struct RecoveryResult: Sendable {
    public let dateKey: String
    /// Recovery-Score 1–99 %.
    public let score: Int
    public let zone: RecoveryZone
    public let components: [RecoveryComponent]
    /// True, solange die Baselines (< 5 Nächte) noch nicht belastbar sind.
    public let calibrating: Bool
    public let hrvValue: Double?
    public let hrvBaseline: Baseline?
    public let rhrValue: Double?
    public let rhrBaseline: Baseline?
}

/// Whoop-artiger Recovery-Score: HRV und Ruhepuls werden gegen die persönliche
/// 30-Tage-Baseline verglichen (HRV logarithmiert, da rechtsschief verteilt),
/// dazu Schlafperformance und Atemfrequenz-Abweichung.
public enum RecoveryEngine {
    public static let weights: [String: Double] = [
        "hrv": 0.40,
        "rhr": 0.25,
        "sleep": 0.25,
        "resp": 0.10,
    ]

    public static func compute(
        dateKey: String,
        today: DayRecord,
        history: [DayRecord],
        sleepPerformance: Double?
    ) -> RecoveryResult? {
        guard today.hrvRmssd != nil || today.restingHR != nil else { return nil }

        let hrvHistory = history.compactMap { $0.hrvRmssd }.suffix(30).map { log($0) }
        let rhrHistory = history.compactMap { $0.restingHR }.suffix(30)
        let respHistory = history.compactMap { $0.respiratoryRate }.suffix(30)
        let tempHistory = history.compactMap { $0.bodyTemp }.suffix(30)

        let hrvBaseline = Stats.baseline(Array(hrvHistory))
        let rhrBaseline = Stats.baseline(Array(rhrHistory))
        let respBaseline = Stats.baseline(Array(respHistory))
        let tempBaseline = Stats.baseline(Array(tempHistory))

        var raw: [(key: String, label: String, score: Double, detail: String)] = []

        if let hrv = today.hrvRmssd {
            let score: Double
            var detail = String(format: "%.0f ms", hrv)
            if let baseline = hrvBaseline {
                let z = baseline.z(log(hrv), minSD: 0.03)
                score = Stats.logistic(z * 1.1)
                detail = String(format: "%.0f ms · Ø %.0f ms", hrv, exp(baseline.mean))
            } else {
                score = 0.5
            }
            raw.append(("hrv", "HRV", score, detail))
        }

        if let rhr = today.restingHR {
            let score: Double
            var detail = String(format: "%.0f S/min", rhr)
            if let baseline = rhrBaseline {
                let z = baseline.z(rhr, minSD: 0.8)
                score = Stats.logistic(-z * 1.1)
                detail = String(format: "%.0f S/min · Ø %.0f", rhr, baseline.mean)
            } else {
                score = 0.5
            }
            raw.append(("rhr", "Ruhepuls", score, detail))
        }

        if let performance = sleepPerformance {
            let score = Stats.clamp(performance / 100, 0.1, 1.0)
            raw.append(("sleep", "Schlaf", score, String(format: "%.0f %% Performance", performance)))
        }

        if let resp = today.respiratoryRate {
            let score: Double
            var detail = String(format: "%.1f /min", resp)
            if let baseline = respBaseline {
                let z = baseline.z(resp, minSD: 0.25)
                score = Stats.clamp(0.85 - max(0, z - 0.3) * 0.2, 0.2, 0.85)
                detail = String(format: "%.1f /min · Ø %.1f", resp, baseline.mean)
            } else {
                score = 0.65
            }
            raw.append(("resp", "Atemfrequenz", score, detail))
        }

        let totalWeight = raw.reduce(0) { $0 + (weights[$1.key] ?? 0) }
        guard totalWeight > 0 else { return nil }

        var components: [RecoveryComponent] = []
        var weighted = 0.0
        for entry in raw {
            let weight = (weights[entry.key] ?? 0) / totalWeight
            weighted += entry.score * weight
            components.append(RecoveryComponent(
                key: entry.key,
                label: entry.label,
                score01: entry.score,
                weight: weight,
                detail: entry.detail
            ))
        }

        var score = weighted * 100

        // Abzüge für Warnsignale
        if let spo2Min = today.spo2Min, spo2Min < 90 {
            score -= 7
        }
        if let temp = today.bodyTemp, let baseline = tempBaseline, baseline.z(temp, minSD: 0.15) > 1.8 {
            score -= 5
        }

        let final = Int(Stats.clamp(score, 1, 99).rounded())
        let zone: RecoveryZone = final >= 67 ? .green : (final >= 34 ? .yellow : .red)
        let calibrating = !(hrvBaseline?.isReliable ?? false) || !(rhrBaseline?.isReliable ?? false)

        return RecoveryResult(
            dateKey: dateKey,
            score: final,
            zone: zone,
            components: components,
            calibrating: calibrating,
            hrvValue: today.hrvRmssd,
            hrvBaseline: hrvBaseline,
            rhrValue: today.restingHR,
            rhrBaseline: rhrBaseline
        )
    }
}

import Foundation

// MARK: - Age reference curves

/// Sex- and age-dependent reference curves for the "Pulse Age" score.
///
/// Basis:
/// - **VO₂max** (backbone): FRIEND registry, 50th percentile, treadmill
///   (Kaminsky et al., Mayo Clin Proc 2015; ~10 % decline per decade).
///   VO₂max is the strongest single predictor of all-cause mortality
///   (Mandsager et al., JAMA Netw Open 2018, 122,007 people).
/// - **HRV (RMSSD)**: age-correlated decline ~1–3 %/year from the mid-20s
///   (review Shaffer & Ginsberg 2017; reference values per decade).
/// - **Resting HR**: +10 bpm ≈ hazard ratio 1.09 for all-cause mortality
///   (meta-analysis Zhang et al., CMAJ 2016, 1.2 million people).
///
/// The curves are piecewise linear between decade anchor points and are
/// inverted to derive an "equivalent age" from a measured value.
public enum AgeNorms {
    /// VO₂max median (ml/kg/min) at decade midpoints (FRIEND, treadmill).
    static let vo2maxMale: [(age: Double, value: Double)] =
        [(25, 48.0), (35, 44.6), (45, 40.3), (55, 35.0), (65, 29.4), (75, 24.4)]
    static let vo2maxFemale: [(age: Double, value: Double)] =
        [(25, 37.6), (35, 34.1), (45, 30.9), (55, 27.1), (65, 22.6), (75, 18.3)]

    /// RMSSD reference (ms) at age midpoints (across sexes;
    /// sex differences are small and inconsistent here).
    static let rmssdRef: [(age: Double, value: Double)] =
        [(25, 60), (35, 46), (45, 36), (55, 29), (65, 23)]

    static func vo2maxCurve(_ sex: BiologicalSex) -> [(age: Double, value: Double)] {
        switch sex {
        case .male: return vo2maxMale
        case .female: return vo2maxFemale
        case .unspecified:
            return zip(vo2maxMale, vo2maxFemale).map { ($0.age, ($0.value + $1.value) / 2) }
        }
    }

    /// Reference resting HR (bpm); women are slightly higher on average.
    static func restingHRRef(_ sex: BiologicalSex) -> Double {
        switch sex {
        case .male: return 60
        case .female: return 63
        case .unspecified: return 61
        }
    }

    /// VO₂max norm value for a given age.
    public static func vo2max(age: Double, sex: BiologicalSex) -> Double {
        interpolate(vo2maxCurve(sex), at: age)
    }

    /// Fitness age: the age at which this VO₂max matches the norm median.
    /// Lower bound 20, because the FRIEND reference only starts at the 20–29 group
    /// and VO₂max is flat in youth — extrapolating lower would be arbitrary.
    public static func fitnessAge(vo2max: Double, sex: BiologicalSex) -> Double {
        invertDecreasing(vo2maxCurve(sex), value: vo2max, clampTo: 20...90)
    }

    /// HRV equivalent age from overnight RMSSD.
    public static func hrvAge(rmssd: Double) -> Double {
        invertDecreasing(rmssdRef, value: rmssd, clampTo: 18...85)
    }

    // MARK: - Piecewise-linear interpolation & inversion

    /// Value at position `at`; extrapolates at the edges with the edge slope.
    static func interpolate(_ points: [(age: Double, value: Double)], at x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.age {
            let p1 = points[0], p2 = points[1]
            return lerp(p1, p2, x)
        }
        if x >= last.age {
            let p1 = points[points.count - 2], p2 = points[points.count - 1]
            return lerp(p1, p2, x)
        }
        for i in 1..<points.count where x <= points[i].age {
            return lerp(points[i - 1], points[i], x)
        }
        return last.value
    }

    private static func lerp(_ a: (age: Double, value: Double), _ b: (age: Double, value: Double), _ x: Double) -> Double {
        let t = (x - a.age) / (b.age - a.age)
        return a.value + t * (b.value - a.value)
    }

    /// Inverts a monotonically **decreasing** curve (value → age).
    /// Extrapolates at the edges and clamps to `clampTo`.
    static func invertDecreasing(_ points: [(age: Double, value: Double)], value v: Double, clampTo range: ClosedRange<Double>) -> Double {
        // Curve falls with increasing age: higher value ⇒ younger.
        if v >= points.first!.value {
            let p1 = points[0], p2 = points[1]
            return Stats.clamp(invLerp(p1, p2, v), range.lowerBound, range.upperBound)
        }
        if v <= points.last!.value {
            let p1 = points[points.count - 2], p2 = points[points.count - 1]
            return Stats.clamp(invLerp(p1, p2, v), range.lowerBound, range.upperBound)
        }
        for i in 1..<points.count where v >= points[i].value {
            return Stats.clamp(invLerp(points[i - 1], points[i], v), range.lowerBound, range.upperBound)
        }
        return Stats.clamp(points.last!.age, range.lowerBound, range.upperBound)
    }

    private static func invLerp(_ a: (age: Double, value: Double), _ b: (age: Double, value: Double), _ v: Double) -> Double {
        let denom = b.value - a.value
        guard abs(denom) > 1e-9 else { return a.age }
        let t = (v - a.value) / denom
        return a.age + t * (b.age - a.age)
    }
}

// MARK: - Inputs & result

/// Aggregated inputs for the AgeEngine (intentionally pre-condensed so the
/// engine stays pure and testable without a store).
public struct AgeInputs: Sendable {
    public var chronoAge: Int
    public var sex: BiologicalSex
    /// Measured VO₂max daily values in the window (Google Health, native).
    public var vo2maxValues: [Double]
    public var rmssdValues: [Double]
    public var restingHRValues: [Double]
    /// Robust observed max HR (p97.5 of intraday HR) or nil.
    public var observedMaxHR: Double?
    public var maxHROverride: Double?
    /// Sleep performance per day (0–100).
    public var sleepPerformances: [Double]
    /// Steps per day.
    public var stepsValues: [Double]
    /// Number of days in the window with at least one recovery value (HRV or RHR).
    public var validDayCount: Int

    public init(
        chronoAge: Int,
        sex: BiologicalSex,
        vo2maxValues: [Double] = [],
        rmssdValues: [Double] = [],
        restingHRValues: [Double] = [],
        observedMaxHR: Double? = nil,
        maxHROverride: Double? = nil,
        sleepPerformances: [Double] = [],
        stepsValues: [Double] = [],
        validDayCount: Int = 0
    ) {
        self.chronoAge = chronoAge
        self.sex = sex
        self.vo2maxValues = vo2maxValues
        self.rmssdValues = rmssdValues
        self.restingHRValues = restingHRValues
        self.observedMaxHR = observedMaxHR
        self.maxHROverride = maxHROverride
        self.sleepPerformances = sleepPerformances
        self.stepsValues = stepsValues
        self.validDayCount = validDayCount
    }
}

public struct AgeComponent: Sendable, Identifiable {
    public enum Kind: Sendable {
        /// Standalone equivalent age (VO₂max, HRV).
        case equivalent
        /// Capped correction in years (resting HR, sleep, activity).
        case adjustment
    }
    public let key: String
    public let label: String
    public let detail: String
    /// Signed years vs. chronological age (negative = younger).
    public let deltaYears: Double
    public let kind: Kind

    public var id: String { key }
}

public struct AgeResult: Sendable {
    public let dateKey: String
    public let chronoAge: Int
    /// Biological "Pulse Age" in years; nil while there is not enough data.
    public let pulseAge: Double?
    public let components: [AgeComponent]
    public let vo2max: Double?
    /// true if VO₂max was estimated via the heart-rate ratio (not measured).
    public let vo2maxEstimated: Bool
    public let fitnessAge: Double?
    public let calibrating: Bool
    public let calibrationHave: Int
    public let calibrationNeed: Int

    public var deltaYears: Double? {
        pulseAge.map { $0 - Double(chronoAge) }
    }
}

// MARK: - Engine

/// Computes a biological "Pulse Age" from the wearable data.
///
/// Structure (see [AgeNorms] for sources):
/// 1. **Backbone = VO₂max → fitness age.** Prefers the value measured by
///    Google Health; if missing, it is estimated via the heart-rate ratio method
///    (Uth et al. 2004: `VO₂max ≈ 15.3 × HRmax/HRrest`).
/// 2. **HRV → HRV age** as a second equivalent age.
/// 3. Both are averaged with weights (VO₂max 0.7 / HRV 0.3).
/// 4. **Capped corrections** from resting HR, sleep and activity (sum ±5 y).
///
/// Important against double counting: the resting HR adjustment is dropped when VO₂max
/// was **estimated** — resting HR is then already part of the backbone.
public enum AgeEngine {
    public static let fitnessWeight = 0.7
    public static let hrvWeight = 0.3
    public static let calibrationNeed = 30
    static let minProvisionalDays = 14

    /// Uth proportionality factor of the heart-rate ratio method.
    static let uthFactor = 15.3

    public static func compute(dateKey: String, inputs: AgeInputs, language: PulseLanguage = .de) -> AgeResult {
        let de = (language == .de)
        let chrono = Double(inputs.chronoAge)
        let have = min(inputs.validDayCount, calibrationNeed)

        // --- Backbone: determine VO₂max (measured OR estimated) ---
        var vo2: Double?
        var vo2Estimated = false

        if let measured = median(inputs.vo2maxValues), inputs.vo2maxValues.count >= 3 {
            vo2 = measured
        } else if let rhr = median(inputs.restingHRValues), inputs.restingHRValues.count >= 5 {
            // Estimated: robust max HR (observed) or the Nes/HUNT formula.
            let hrMax = inputs.maxHROverride
                ?? trustworthyMaxHR(inputs.observedMaxHR)
                ?? (211 - 0.64 * chrono)
            if hrMax > rhr + 20 {
                vo2 = Stats.clamp(uthFactor * hrMax / rhr, 15, 80)
                vo2Estimated = true
            }
        }

        let fitnessAge = vo2.map { AgeNorms.fitnessAge(vo2max: $0, sex: inputs.sex) }

        // --- HRV age (second equivalent age) ---
        var hrvAge: Double?
        if inputs.rmssdValues.count >= 7, let rmssd = median(inputs.rmssdValues) {
            hrvAge = AgeNorms.hrvAge(rmssd: rmssd)
        }

        // --- Core = weighted mean of the available equivalent ages ---
        var core: Double?
        var weightPairs: [(Double, Double)] = []
        if let fitnessAge { weightPairs.append((fitnessAge, fitnessWeight)) }
        if let hrvAge { weightPairs.append((hrvAge, hrvWeight)) }
        if !weightPairs.isEmpty {
            let wSum = weightPairs.reduce(0) { $0 + $1.1 }
            core = weightPairs.reduce(0) { $0 + $1.0 * $1.1 } / wSum
        }

        // --- Capped corrections ---
        // Resting HR: only if VO₂max was MEASURED (otherwise double counting, because
        // the estimate carries resting HR in the denominator).
        var rhrDelta: Double?
        let allowRHR = !vo2Estimated
        if allowRHR, let rhr = median(inputs.restingHRValues), inputs.restingHRValues.count >= 5 {
            let ref = AgeNorms.restingHRRef(inputs.sex)
            // +10 bpm ≈ 2.5 "aging years" (conservative heuristic from the
            // mortality HR 1.09/10 bpm), capped to ±3 years.
            rhrDelta = Stats.clamp((rhr - ref) / 10 * 2.5, -3, 3)
        }

        // Sleep: mean performance vs. ~78 % target corridor, capped ±1.5.
        var sleepDelta: Double?
        if !inputs.sleepPerformances.isEmpty {
            let perf = Stats.mean(inputs.sleepPerformances)
            sleepDelta = Stats.clamp((78 - perf) / 12, -1.5, 1.5)
        }

        // Activity: average steps vs. ~8000/day, capped ±1.5.
        var activityDelta: Double?
        if !inputs.stepsValues.isEmpty {
            let steps = Stats.mean(inputs.stepsValues)
            let ratio = Stats.clamp(steps / 8000, 0, 1.6)
            activityDelta = Stats.clamp((1 - ratio) * 1.5, -1.5, 1.5)
        }

        // --- Calibration & result assembly ---
        let backboneResolvable = (vo2 != nil)
        let hasEnoughDays = inputs.validDayCount >= minProvisionalDays
        let calibrating = inputs.validDayCount < calibrationNeed || !backboneResolvable

        var components: [AgeComponent] = []
        if let vo2, let fitnessAge {
            let estimated = vo2Estimated ? (de ? " (geschätzt)" : " (estimated)") : ""
            components.append(AgeComponent(
                key: "fitness",
                label: de ? "Fitness (VO₂max)" : "Fitness (VO₂max)",
                detail: String(format: de ? "%.0f ml/kg/min%@ · Fitness-Alter %.0f" : "%.0f ml/kg/min%@ · fitness age %.0f",
                               vo2, estimated, fitnessAge),
                deltaYears: fitnessAge - chrono,
                kind: .equivalent
            ))
        }
        if let hrvAge, let rmssd = median(inputs.rmssdValues) {
            components.append(AgeComponent(
                key: "hrv",
                label: "HRV",
                detail: String(format: de ? "%.0f ms · HRV-Alter %.0f" : "%.0f ms · HRV age %.0f", rmssd, hrvAge),
                deltaYears: hrvAge - chrono,
                kind: .equivalent
            ))
        }
        if let rhrDelta, let rhr = median(inputs.restingHRValues) {
            components.append(AgeComponent(
                key: "rhr",
                label: de ? "Ruhepuls" : "Resting HR",
                detail: String(format: de ? "%.0f S/min" : "%.0f bpm", rhr),
                deltaYears: rhrDelta,
                kind: .adjustment
            ))
        }
        if let sleepDelta {
            components.append(AgeComponent(
                key: "sleep",
                label: de ? "Schlaf" : "Sleep",
                detail: String(format: de ? "Ø %.0f %% Performance" : "avg %.0f %% performance", Stats.mean(inputs.sleepPerformances)),
                deltaYears: sleepDelta,
                kind: .adjustment
            ))
        }
        if let activityDelta {
            components.append(AgeComponent(
                key: "activity",
                label: de ? "Aktivität" : "Activity",
                detail: String(format: de ? "Ø %.0f Schritte/Tag" : "avg %.0f steps/day", Stats.mean(inputs.stepsValues)),
                deltaYears: activityDelta,
                kind: .adjustment
            ))
        }

        // Only show Pulse Age if the backbone is resolvable AND there are enough days.
        var pulseAge: Double?
        if backboneResolvable, hasEnoughDays, let core {
            let offsets = Stats.clamp(
                (rhrDelta ?? 0) + (sleepDelta ?? 0) + (activityDelta ?? 0),
                -5, 5
            )
            pulseAge = Stats.clamp(core + offsets, 15, 95)
        }

        return AgeResult(
            dateKey: dateKey,
            chronoAge: inputs.chronoAge,
            pulseAge: pulseAge,
            components: components,
            vo2max: vo2,
            vo2maxEstimated: vo2Estimated,
            fitnessAge: fitnessAge,
            calibrating: calibrating,
            calibrationHave: have,
            calibrationNeed: calibrationNeed
        )
    }

    // MARK: - Helpers

    /// Only trust the observed max HR if it is physiologically plausible.
    static func trustworthyMaxHR(_ value: Double?) -> Double? {
        guard let value, value >= 150, value <= 220 else { return nil }
        return value
    }

    static func median(_ values: [Double]) -> Double? {
        Stats.percentile(values, 0.5)
    }
}

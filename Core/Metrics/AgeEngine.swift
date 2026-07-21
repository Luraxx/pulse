import Foundation

// MARK: - Alters-Normkurven

/// Geschlechts- und altersabhängige Referenzkurven für den „Pulse Alter"-Score.
///
/// Grundlage:
/// - **VO₂max** (Rückgrat): FRIEND-Register, 50. Perzentil, Laufband
///   (Kaminsky et al., Mayo Clin Proc 2015; ~10 % Rückgang pro Dekade).
///   VO₂max ist der stärkste Einzelprädiktor der Gesamtmortalität
///   (Mandsager et al., JAMA Netw Open 2018, 122 007 Personen).
/// - **HRV (RMSSD)**: alterskorrelierter Rückgang ~1–3 %/Jahr ab Mitte 20
///   (Übersicht Shaffer & Ginsberg 2017; Referenzwerte pro Dekade).
/// - **Ruhepuls**: +10 S/min ≈ Hazard-Ratio 1,09 für Gesamtmortalität
///   (Meta-Analyse Zhang et al., CMAJ 2016, 1,2 Mio. Personen).
///
/// Die Kurven sind stückweise linear zwischen Dekaden-Stützstellen und werden
/// invertiert, um aus einem Messwert ein „Äquivalenzalter" zu bestimmen.
public enum AgeNorms {
    /// VO₂max-Median (ml/kg/min) an den Dekaden-Mittelpunkten (FRIEND, Laufband).
    static let vo2maxMale: [(age: Double, value: Double)] =
        [(25, 48.0), (35, 44.6), (45, 40.3), (55, 35.0), (65, 29.4), (75, 24.4)]
    static let vo2maxFemale: [(age: Double, value: Double)] =
        [(25, 37.6), (35, 34.1), (45, 30.9), (55, 27.1), (65, 22.6), (75, 18.3)]

    /// RMSSD-Referenz (ms) an Alters-Mittelpunkten (geschlechtsübergreifend;
    /// die Geschlechtsunterschiede sind hier klein und uneinheitlich).
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

    /// Referenz-Ruhepuls (S/min); Frauen liegen im Mittel leicht höher.
    static func restingHRRef(_ sex: BiologicalSex) -> Double {
        switch sex {
        case .male: return 60
        case .female: return 63
        case .unspecified: return 61
        }
    }

    /// VO₂max-Normwert für ein gegebenes Alter.
    public static func vo2max(age: Double, sex: BiologicalSex) -> Double {
        interpolate(vo2maxCurve(sex), at: age)
    }

    /// Fitness-Alter: das Alter, bei dem dieser VO₂max dem Normmedian entspricht.
    /// Untergrenze 20, weil die FRIEND-Referenz erst ab der Gruppe 20–29 beginnt
    /// und VO₂max in der Jugend flach ist — tiefer zu extrapolieren wäre Willkür.
    public static func fitnessAge(vo2max: Double, sex: BiologicalSex) -> Double {
        invertDecreasing(vo2maxCurve(sex), value: vo2max, clampTo: 20...90)
    }

    /// HRV-Äquivalenzalter aus dem nächtlichen RMSSD.
    public static func hrvAge(rmssd: Double) -> Double {
        invertDecreasing(rmssdRef, value: rmssd, clampTo: 18...85)
    }

    // MARK: - Stückweise-lineare Interpolation & Inversion

    /// Wert an Position `at`; extrapoliert an den Rändern mit der Randsteigung.
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

    /// Invertiert eine monoton **fallende** Kurve (value → age).
    /// Extrapoliert an den Rändern und klemmt auf `clampTo`.
    static func invertDecreasing(_ points: [(age: Double, value: Double)], value v: Double, clampTo range: ClosedRange<Double>) -> Double {
        // Kurve fällt mit steigendem Alter: höherer Wert ⇒ jünger.
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

// MARK: - Eingaben & Ergebnis

/// Aggregierte Eingaben für die AgeEngine (bewusst vorverdichtet, damit die
/// Engine rein und ohne Store testbar bleibt).
public struct AgeInputs: Sendable {
    public var chronoAge: Int
    public var sex: BiologicalSex
    /// Gemessene VO₂max-Tageswerte im Fenster (Google Health, nativ).
    public var vo2maxValues: [Double]
    public var rmssdValues: [Double]
    public var restingHRValues: [Double]
    /// Robuster beobachteter Maximalpuls (p97,5 der Intraday-HF) oder nil.
    public var observedMaxHR: Double?
    public var maxHROverride: Double?
    /// Schlafperformance je Tag (0–100).
    public var sleepPerformances: [Double]
    /// Schritte je Tag.
    public var stepsValues: [Double]
    /// Anzahl Tage im Fenster mit mind. einem Recovery-Messwert (HRV oder RHR).
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
        /// Eigenständiges Äquivalenzalter (VO₂max, HRV).
        case equivalent
        /// Gedeckelte Korrektur in Jahren (Ruhepuls, Schlaf, Aktivität).
        case adjustment
    }
    public let key: String
    public let label: String
    public let detail: String
    /// Vorzeichenbehaftete Jahre ggü. dem chronologischen Alter (negativ = jünger).
    public let deltaYears: Double
    public let kind: Kind

    public var id: String { key }
}

public struct AgeResult: Sendable {
    public let dateKey: String
    public let chronoAge: Int
    /// Biologisches „Pulse Alter" in Jahren; nil, solange nicht genug Daten.
    public let pulseAge: Double?
    public let components: [AgeComponent]
    public let vo2max: Double?
    /// true, wenn VO₂max über die Herzfrequenz-Ratio geschätzt (nicht gemessen) wurde.
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

/// Berechnet ein biologisches „Pulse Alter" aus den Wearable-Daten.
///
/// Aufbau (siehe [AgeNorms] für Quellen):
/// 1. **Rückgrat = VO₂max → Fitness-Alter.** Bevorzugt der von Google Health
///    gemessene Wert; fehlt er, wird er über die Herzfrequenz-Ratio-Methode
///    geschätzt (Uth et al. 2004: `VO₂max ≈ 15,3 × HRmax/HRruhe`).
/// 2. **HRV → HRV-Alter** als zweites Äquivalenzalter.
/// 3. Beide werden gewichtet gemittelt (VO₂max 0,7 / HRV 0,3).
/// 4. **Gedeckelte Korrekturen** aus Ruhepuls, Schlaf und Aktivität (Summe ±5 J.).
///
/// Wichtig gegen Doppelzählung: Der Ruhepuls-Zuschlag entfällt, wenn VO₂max
/// **geschätzt** wurde — dann steckt der Ruhepuls bereits im Rückgrat.
public enum AgeEngine {
    public static let fitnessWeight = 0.7
    public static let hrvWeight = 0.3
    public static let calibrationNeed = 30
    static let minProvisionalDays = 14

    /// Uth-Proportionalitätsfaktor der Herzfrequenz-Ratio-Methode.
    static let uthFactor = 15.3

    public static func compute(dateKey: String, inputs: AgeInputs, language: PulseLanguage = .de) -> AgeResult {
        let de = (language == .de)
        let chrono = Double(inputs.chronoAge)
        let have = min(inputs.validDayCount, calibrationNeed)

        // --- Rückgrat: VO₂max bestimmen (gemessen ODER geschätzt) ---
        var vo2: Double?
        var vo2Estimated = false

        if let measured = median(inputs.vo2maxValues), inputs.vo2maxValues.count >= 3 {
            vo2 = measured
        } else if let rhr = median(inputs.restingHRValues), inputs.restingHRValues.count >= 5 {
            // Geschätzt: robuster Maxpuls (beobachtet) oder Nes/HUNT-Formel.
            let hrMax = inputs.maxHROverride
                ?? trustworthyMaxHR(inputs.observedMaxHR)
                ?? (211 - 0.64 * chrono)
            if hrMax > rhr + 20 {
                vo2 = Stats.clamp(uthFactor * hrMax / rhr, 15, 80)
                vo2Estimated = true
            }
        }

        let fitnessAge = vo2.map { AgeNorms.fitnessAge(vo2max: $0, sex: inputs.sex) }

        // --- HRV-Alter (zweites Äquivalenzalter) ---
        var hrvAge: Double?
        if inputs.rmssdValues.count >= 7, let rmssd = median(inputs.rmssdValues) {
            hrvAge = AgeNorms.hrvAge(rmssd: rmssd)
        }

        // --- Kern = gewichtetes Mittel der verfügbaren Äquivalenzalter ---
        var core: Double?
        var weightPairs: [(Double, Double)] = []
        if let fitnessAge { weightPairs.append((fitnessAge, fitnessWeight)) }
        if let hrvAge { weightPairs.append((hrvAge, hrvWeight)) }
        if !weightPairs.isEmpty {
            let wSum = weightPairs.reduce(0) { $0 + $1.1 }
            core = weightPairs.reduce(0) { $0 + $1.0 * $1.1 } / wSum
        }

        // --- Gedeckelte Korrekturen ---
        // Ruhepuls: nur wenn VO₂max GEMESSEN wurde (sonst Doppelzählung, weil die
        // Schätzung den Ruhepuls im Nenner trägt).
        var rhrDelta: Double?
        let allowRHR = !vo2Estimated
        if allowRHR, let rhr = median(inputs.restingHRValues), inputs.restingHRValues.count >= 5 {
            let ref = AgeNorms.restingHRRef(inputs.sex)
            // +10 S/min ≈ 2,5 „Alterungsjahre" (konservative Heuristik aus der
            // Mortalitäts-HR 1,09/10 bpm), gedeckelt auf ±3 Jahre.
            rhrDelta = Stats.clamp((rhr - ref) / 10 * 2.5, -3, 3)
        }

        // Schlaf: mittlere Performance ggü. ~78 % Zielkorridor, gedeckelt ±1,5.
        var sleepDelta: Double?
        if !inputs.sleepPerformances.isEmpty {
            let perf = Stats.mean(inputs.sleepPerformances)
            sleepDelta = Stats.clamp((78 - perf) / 12, -1.5, 1.5)
        }

        // Aktivität: Schrittschnitt ggü. ~8000/Tag, gedeckelt ±1,5.
        var activityDelta: Double?
        if !inputs.stepsValues.isEmpty {
            let steps = Stats.mean(inputs.stepsValues)
            let ratio = Stats.clamp(steps / 8000, 0, 1.6)
            activityDelta = Stats.clamp((1 - ratio) * 1.5, -1.5, 1.5)
        }

        // --- Kalibrierung & Ergebnis-Zusammenbau ---
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

        // Pulse-Alter nur zeigen, wenn Rückgrat auflösbar UND genug Tage.
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

    // MARK: - Helfer

    /// Beobachteter Maxpuls nur vertrauen, wenn er physiologisch plausibel ist.
    static func trustworthyMaxHR(_ value: Double?) -> Double? {
        guard let value, value >= 150, value <= 220 else { return nil }
        return value
    }

    static func median(_ values: [Double]) -> Double? {
        Stats.percentile(values, 0.5)
    }
}

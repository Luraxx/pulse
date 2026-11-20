import Foundation

/// App language. Intentionally a lightweight custom layer instead of system localization:
/// the user switches in the app and the change applies immediately (no restart).
public enum PulseLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case de
    case en

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }

    /// System language as a sensible first-launch default.
    public static var systemDefault: PulseLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("de") ? .de : .en
    }

    /// Identifier for formatting locales.
    public var localeIdentifier: String {
        switch self {
        case .de: return "de_DE"
        case .en: return "en_US"
        }
    }
}

// MARK: - Localized labels of the Core types

public extension JournalFactor {
    func label(_ lang: PulseLanguage) -> String {
        switch (self, lang) {
        case (.alcohol, .de): return "Alkohol"
        case (.alcohol, .en): return "Alcohol"
        case (.lateCaffeine, .de): return "Koffein spät"
        case (.lateCaffeine, .en): return "Late caffeine"
        case (.lateMeal, .de): return "Spätes Essen"
        case (.lateMeal, .en): return "Late meal"
        case (.stress, .de): return "Stress"
        case (.stress, .en): return "Stress"
        case (.sick, .de): return "Krank"
        case (.sick, .en): return "Sick"
        case (.screenBeforeBed, .de): return "Bildschirm vor dem Schlaf"
        case (.screenBeforeBed, .en): return "Screen before bed"
        case (.exercised, .de): return "Trainiert"
        case (.exercised, .en): return "Worked out"
        case (.sex, .de): return "Sex"
        case (.sex, .en): return "Sex"
        }
    }
}

public extension BiologicalSex {
    func label(_ lang: PulseLanguage) -> String {
        switch (self, lang) {
        case (.male, .de): return "Männlich"
        case (.male, .en): return "Male"
        case (.female, .de): return "Weiblich"
        case (.female, .en): return "Female"
        case (.unspecified, .de): return "Keine Angabe"
        case (.unspecified, .en): return "Not specified"
        }
    }
}

public extension HealthMetricKind {
    func label(_ lang: PulseLanguage) -> String {
        switch (self, lang) {
        case (.restingHR, .de): return "Ruhepuls"
        case (.restingHR, .en): return "Resting HR"
        case (.hrv, _): return "HRV"
        case (.respiratoryRate, .de): return "Atemfrequenz"
        case (.respiratoryRate, .en): return "Respiratory rate"
        case (.spo2, _): return "SpO₂"
        case (.bodyTemp, .de): return "Hauttemperatur"
        case (.bodyTemp, .en): return "Skin temperature"
        }
    }

    func unit(_ lang: PulseLanguage) -> String {
        switch (self, lang) {
        case (.restingHR, .de): return "S/min"
        case (.restingHR, .en): return "bpm"
        case (.hrv, _): return "ms"
        case (.respiratoryRate, _): return "/min"
        case (.spo2, _): return "%"
        case (.bodyTemp, _): return "°C"
        }
    }
}

public extension StrainEngine {
    static func zoneLabels(_ lang: PulseLanguage) -> [String] {
        switch lang {
        case .de: return zoneLabels
        case .en: return ["Very light", "Light", "Moderate", "Demanding", "Hard", "Max"]
        }
    }
}

public extension HealthMonitor {
    /// Localized variant of the warning (the parameterless one stays German).
    static func alert(records: [DayRecord], lookback: Int = 3, language: PulseLanguage) -> HealthAlert? {
        guard let base = alert(records: records, lookback: lookback) else { return nil }
        guard language == .en else { return base }

        // Rephrase the message in English (same rules as in the core).
        if base.kinds.count >= 2 {
            let names = base.kinds.map { $0.label(.en) }.sorted().joined(separator: ", ")
            return HealthAlert(
                kinds: base.kinds,
                message: "\(base.kinds.count) values outside your baseline (\(names)) – possible infection or overtraining. Take it easy today.",
                isWarning: base.isWarning
            )
        }
        if let kind = base.kinds.first {
            let direction: String
            switch kind {
            case .hrv, .spo2: direction = "low"
            case .restingHR, .respiratoryRate, .bodyTemp: direction = "elevated"
            }
            // Streak length is embedded in the German text; robust: phrase it generically.
            return HealthAlert(
                kinds: base.kinds,
                message: "\(kind.label(.en)) has been \(direction) for 2+ days – prioritize recovery.",
                isWarning: base.isWarning
            )
        }
        return base
    }
}

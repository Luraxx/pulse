import Foundation

// MARK: - Journal-Faktoren

/// Verhaltens-Faktoren, die abends abgehakt werden. Bewusst eine feste, kleine
/// Liste (kein Freitext-Wildwuchs), damit Korrelationen belastbar bleiben.
public enum JournalFactor: String, Codable, CaseIterable, Sendable, Identifiable {
    case alcohol
    case lateCaffeine
    case lateMeal
    case stress
    case sick
    case screenBeforeBed
    case exercised
    case sex

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .alcohol: return "Alkohol"
        case .lateCaffeine: return "Koffein spät"
        case .lateMeal: return "Spätes Essen"
        case .stress: return "Stress"
        case .sick: return "Krank"
        case .screenBeforeBed: return "Bildschirm vor dem Schlaf"
        case .exercised: return "Trainiert"
        case .sex: return "Sex"
        }
    }

    public var symbol: String {
        switch self {
        case .alcohol: return "wineglass"
        case .lateCaffeine: return "cup.and.saucer"
        case .lateMeal: return "fork.knife"
        case .stress: return "bolt.heart"
        case .sick: return "thermometer.medium"
        case .screenBeforeBed: return "iphone"
        case .exercised: return "figure.run"
        case .sex: return "heart.fill"
        }
    }
}

/// Journal-Eintrag eines Tages: welche Faktoren an diesem Tag zutrafen.
public struct JournalEntry: Codable, Sendable {
    public var date: String // "yyyy-MM-dd"
    public var factors: Set<JournalFactor>

    public init(date: String, factors: Set<JournalFactor> = []) {
        self.date = date
        self.factors = factors
    }
}

// MARK: - Journal-Speicher

/// Persistiert Journal-Einträge in einer **eigenen** JSON-Datei — getrennt vom
/// MetricsStore, damit ein Sync (der `days.json` ersetzt) das Journal nie
/// überschreibt.
public final class JournalStore {
    public private(set) var entries: [String: JournalEntry] = [:]
    public let fileURL: URL

    public init(directory: URL, filename: String = "journal.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: JournalEntry].self, from: data) else { return }
        entries = decoded
    }

    @discardableResult
    public func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    public func entry(for key: String) -> JournalEntry {
        entries[key] ?? JournalEntry(date: key)
    }

    public func toggle(_ factor: JournalFactor, on key: String) {
        var entry = entry(for: key)
        if entry.factors.contains(factor) {
            entry.factors.remove(factor)
        } else {
            entry.factors.insert(factor)
        }
        entries[key] = entry
    }

    public func isSet(_ factor: JournalFactor, on key: String) -> Bool {
        entries[key]?.factors.contains(factor) ?? false
    }

    public func wipe() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Korrelations-Engine

/// Wie belastbar ein Insight ist.
public enum InsightConfidence: String, Sendable {
    /// Differenz übersteigt das Doppelte ihres Standardfehlers (~95 %-Niveau).
    case solid
    /// Mindestfallzahl erreicht, aber Differenz noch im Rauschbereich.
    case emerging
}

public struct FactorInsight: Sendable, Identifiable {
    public let factor: JournalFactor
    /// Ø Recovery des Folgetags an Tagen MIT dem Faktor.
    public let avgWith: Double
    /// Ø Recovery des Folgetags an Tagen OHNE den Faktor.
    public let avgWithout: Double
    /// Differenz in Recovery-Punkten (negativ = Faktor senkt Recovery).
    public let delta: Double
    /// Standardfehler der Differenz (Welch) — Maß für das Rauschen.
    public let standardError: Double
    public let confidence: InsightConfidence
    public let daysWith: Int
    public let daysWithout: Int

    public var id: String { factor.rawValue }
}

/// Korreliert Journal-Faktoren mit der Recovery des **Folgetags** (die Nacht
/// nach dem Faktor). Methodik angelehnt an Whoops Monthly Performance
/// Assessment: mind. 5 Ja- und 5 Nein-Tage je Verhalten, erste
/// Monats-Auswertung ab 28 Recovery-Tagen; Vergleich der Gruppen-Mittel,
/// Belastbarkeit über den Standardfehler der Differenz (Welch).
/// Korrelation, kein Kausalbeweis — das bleibt in der UI ausgewiesen.
public enum JournalEngine {
    /// Whoop-Regel: mind. 5 Tage mit und 5 ohne das Verhalten.
    public static let minDaysPerGroup = 5
    /// Whoop-Regel: erste Monats-Auswertung ab 28 Tagen mit Recovery-Daten.
    public static let assessmentMinRecoveryDays = 28

    /// Genug Gesamtdaten für eine Monats-Auswertung?
    public static func assessmentReady(recoveryByDay: [String: Int]) -> Bool {
        recoveryByDay.count >= assessmentMinRecoveryDays
    }

    public static func insights(
        entries: [String: JournalEntry],
        recoveryByDay: [String: Int]
    ) -> [FactorInsight] {
        var result: [FactorInsight] = []

        for factor in JournalFactor.allCases {
            var withValues: [Double] = []
            var withoutValues: [Double] = []

            for (dayKey, entry) in entries {
                // Recovery des Folgetags (Wirkung zeigt sich in der Nacht danach).
                let nextKey = DayKey.addDays(dayKey, 1)
                guard let recovery = recoveryByDay[nextKey] else { continue }
                if entry.factors.contains(factor) {
                    withValues.append(Double(recovery))
                } else {
                    withoutValues.append(Double(recovery))
                }
            }

            guard withValues.count >= minDaysPerGroup,
                  withoutValues.count >= minDaysPerGroup else { continue }

            let avgWith = Stats.mean(withValues)
            let avgWithout = Stats.mean(withoutValues)
            let delta = avgWith - avgWithout

            // Welch-Standardfehler der Mittelwert-Differenz.
            let varWith = pow(Stats.standardDeviation(withValues), 2)
            let varWithout = pow(Stats.standardDeviation(withoutValues), 2)
            let se = sqrt(varWith / Double(withValues.count) + varWithout / Double(withoutValues.count))

            result.append(FactorInsight(
                factor: factor,
                avgWith: avgWith,
                avgWithout: avgWithout,
                delta: delta,
                standardError: se,
                confidence: abs(delta) > 2 * max(se, 0.001) ? .solid : .emerging,
                daysWith: withValues.count,
                daysWithout: withoutValues.count
            ))
        }

        // Stärkster (betragsmäßiger) Effekt zuerst.
        return result.sorted { abs($0.delta) > abs($1.delta) }
    }
}

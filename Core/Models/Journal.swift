import Foundation

// MARK: - Journal factors

/// Behavior factors checked off in the evening. Intentionally a fixed, small
/// list (no free-text sprawl) so correlations stay solid.
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

/// Journal entry for a day: which factors applied on that day.
public struct JournalEntry: Codable, Sendable {
    public var date: String // "yyyy-MM-dd"
    public var factors: Set<JournalFactor>

    public init(date: String, factors: Set<JournalFactor> = []) {
        self.date = date
        self.factors = factors
    }
}

// MARK: - Journal storage

/// Persists journal entries in a **separate** JSON file — kept apart from the
/// MetricsStore so a sync (which replaces `days.json`) never overwrites
/// the journal.
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

// MARK: - Correlation engine

/// How solid an insight is.
public enum InsightConfidence: String, Sendable {
    /// Difference exceeds twice its standard error (~95 % level).
    case solid
    /// Minimum sample size reached, but difference still within noise.
    case emerging
}

public struct FactorInsight: Sendable, Identifiable {
    public let factor: JournalFactor
    /// Avg next-day recovery on days WITH the factor.
    public let avgWith: Double
    /// Avg next-day recovery on days WITHOUT the factor.
    public let avgWithout: Double
    /// Difference in recovery points (negative = factor lowers recovery).
    public let delta: Double
    /// Standard error of the difference (Welch) — a measure of noise.
    public let standardError: Double
    public let confidence: InsightConfidence
    public let daysWith: Int
    public let daysWithout: Int

    public var id: String { factor.rawValue }
}

/// Correlates journal factors with the recovery of the **next day** (the night
/// after the factor). Method modeled on Whoop's Monthly Performance
/// Assessment: at least 5 yes and 5 no days per behavior, first
/// monthly assessment from 28 recovery days; compares group means,
/// solidity via the standard error of the difference (Welch).
/// Correlation, not proof of causation — the UI states this.
public enum JournalEngine {
    /// Whoop rule: at least 5 days with and 5 without the behavior.
    public static let minDaysPerGroup = 5
    /// Whoop rule: first monthly assessment from 28 days with recovery data.
    public static let assessmentMinRecoveryDays = 28

    /// Enough overall data for a monthly assessment?
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
                // Next-day recovery (the effect shows in the night after).
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

            // Welch standard error of the difference of means.
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

        // Strongest (absolute) effect first.
        return result.sorted { abs($0.delta) > abs($1.delta) }
    }
}

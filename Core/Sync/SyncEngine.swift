import Foundation

public struct SyncProgress: Sendable {
    public let message: String
    public let fraction: Double

    public init(message: String, fraction: Double) {
        self.message = message
        self.fraction = fraction
    }
}

public struct SyncLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let metric: String
    public let detail: String
    public let isError: Bool

    public init(metric: String, detail: String, isError: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.metric = metric
        self.detail = detail
        self.isError = isError
    }
}

public struct SyncOutcome: Sendable {
    public let updatedDays: [String: DayRecord]
    public let log: [SyncLogEntry]
    public let profile: UserProfile?
    public var hadErrors: Bool { log.contains { $0.isError } }

    public init(updatedDays: [String: DayRecord], log: [SyncLogEntry], profile: UserProfile?) {
        self.updatedDays = updatedDays
        self.log = log
        self.profile = profile
    }
}

/// Orchestriert alle API-Abrufe für ein Zeitfenster. Jede Metrik wird isoliert
/// geladen — ein Fehler (z.B. ein noch nicht verfügbarer Datentyp) blockiert
/// die übrigen Metriken nicht, sondern landet nur im Sync-Log.
public final class SyncEngine: @unchecked Sendable {
    private let client: HealthAPIClient

    public init(client: HealthAPIClient) {
        self.client = client
    }

    public func sync(
        existingDays: [String: DayRecord],
        daysBack: Int,
        hrDaysBack: Int,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async -> SyncOutcome {
        var days = existingDays
        var log: [SyncLogEntry] = []
        var profile: UserProfile?

        let todayKey = DayKey.today()
        let startKey = DayKey.addDays(todayKey, -(max(1, daysBack) - 1))
        guard let windowStart = DayKey.date(from: startKey) else {
            return SyncOutcome(updatedDays: days, log: [SyncLogEntry(metric: "Sync", detail: "Ungültiges Zeitfenster", isError: true)], profile: nil)
        }
        let windowEnd = Date()
        let syncStamp = Date()

        func note(_ metric: String, _ detail: String, error: Bool = false) {
            log.append(SyncLogEntry(metric: metric, detail: detail, isError: error))
        }

        func update(_ key: String, _ mutate: (inout DayRecord) -> Void) {
            guard key >= startKey, key <= todayKey else { return }
            var record = days[key] ?? DayRecord(date: key)
            mutate(&record)
            record.syncedAt = syncStamp
            days[key] = record
        }

        let totalSteps = 10.0
        var currentStep = 0.0
        func report(_ message: String) {
            progress?(SyncProgress(message: message, fraction: min(1, currentStep / totalSteps)))
            currentStep += 1
        }

        // 1. Profil
        report("Profil laden…")
        do {
            profile = try await client.fetchProfile()
            note("Profil", "geladen")
        } catch {
            note("Profil", Self.describe(error), error: true)
        }

        // 2. Schlaf-Sessions (Zuordnung zum Aufwach-Tag)
        report("Schlaf laden…")
        do {
            let sessions = try await client.fetchSleepSessions(
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            var byDay: [String: [SleepSession]] = [:]
            for session in sessions {
                byDay[DayKey.string(from: session.end), default: []].append(session)
            }
            for (key, list) in byDay {
                var sorted = list.sorted { $0.start < $1.start }
                if !sorted.contains(where: { $0.isMainSleep }),
                   let longest = sorted.indices.max(by: { sorted[$0].minutesAsleep < sorted[$1].minutesAsleep }) {
                    sorted[longest].isMainSleep = true
                }
                update(key) { $0.sleepSessions = sorted }
            }
            note("Schlaf", "\(sessions.count) Sessions")
        } catch {
            note("Schlaf", Self.describe(error), error: true)
        }

        // 3. HRV (nächtliche Samples → Mittelwert je Nacht)
        report("HRV laden…")
        do {
            let samples = try await client.fetchSamples(
                type: "heart-rate-variability",
                payloadKey: "heartRateVariability",
                valueKeys: ["rmssd", "rmssdMilliseconds", "milliseconds", "dailyRmssd", "value"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.hrvRmssd = Stats.mean(values) }
            }
            note("HRV", "\(samples.count) Samples, \(grouped.count) Nächte")
        } catch {
            note("HRV", Self.describe(error), error: true)
        }

        // 4. Atemfrequenz
        report("Atemfrequenz laden…")
        do {
            let samples = try await client.fetchSamples(
                type: "respiratory-rate",
                payloadKey: "respiratoryRate",
                valueKeys: ["breathsPerMinute", "rate", "value", "fullSleepSummary"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.respiratoryRate = Stats.mean(values) }
            }
            note("Atemfrequenz", "\(grouped.count) Nächte")
        } catch {
            note("Atemfrequenz", Self.describe(error), error: true)
        }

        // 5. SpO2 (nächtlicher Durchschnitt + Minimum)
        report("SpO₂ laden…")
        do {
            let samples = try await client.fetchSamples(
                type: "oxygen-saturation",
                payloadKey: "oxygenSaturation",
                valueKeys: ["percentage", "averagePercentage", "value"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            var byNight: [String: [Double]] = [:]
            for sample in samples {
                byNight[DayKey.nightKey(for: sample.time), default: []].append(sample.value)
            }
            for (key, values) in byNight where !values.isEmpty {
                update(key) {
                    $0.spo2Avg = Stats.mean(values)
                    $0.spo2Min = values.min()
                }
            }
            note("SpO₂", "\(byNight.count) Nächte")
        } catch {
            note("SpO₂", Self.describe(error), error: true)
        }

        // 6. Temperatur (Haut/Körper, nächtlicher Wert)
        report("Temperatur laden…")
        do {
            let samples = try await client.fetchSamples(
                type: "body-temperature",
                payloadKey: "bodyTemperature",
                valueKeys: ["celsius", "degreesCelsius", "temperature", "value", "nightlyRelative"],
                start: windowStart.addingTimeInterval(-12 * 3600),
                end: windowEnd
            )
            let grouped = Self.groupByNight(samples)
            for (key, values) in grouped {
                update(key) { $0.bodyTemp = Stats.mean(values) }
            }
            note("Temperatur", "\(grouped.count) Nächte")
        } catch {
            note("Temperatur", Self.describe(error), error: true)
        }

        // 7. Ruhepuls (Tagesdatentyp; Fallback später aus Nacht-HR)
        report("Ruhepuls laden…")
        do {
            let values = try await client.fetchDailyValues(
                type: "resting-heart-rate",
                payloadKey: "restingHeartRate",
                valueKeys: ["beatsPerMinute", "bpm", "value"],
                start: windowStart,
                end: windowEnd
            )
            for (key, value) in values {
                update(key) { $0.restingHR = value }
            }
            note("Ruhepuls", "\(values.count) Tage")
        } catch {
            note("Ruhepuls", "\(Self.describe(error)) – Fallback über Nacht-HF aktiv", error: true)
        }

        // 8. Schritte (Intervall-Samples → Tagessumme)
        report("Schritte laden…")
        do {
            let samples = try await client.fetchSamples(
                type: "steps",
                payloadKey: "steps",
                valueKeys: ["count", "steps", "value"],
                start: windowStart,
                end: windowEnd,
                filterField: "interval.start_time"
            )
            var byDay: [String: Double] = [:]
            for sample in samples {
                byDay[DayKey.string(from: sample.time), default: 0] += sample.value
            }
            for (key, total) in byDay {
                update(key) { $0.steps = Int(total) }
            }
            note("Schritte", "\(byDay.count) Tage")
        } catch {
            note("Schritte", Self.describe(error), error: true)
        }

        // 9. Intraday-Herzfrequenz (nur letzte hrDaysBack Tage, 1-min-Downsampling)
        report("Herzfrequenz laden…")
        let hrStartKey = DayKey.addDays(todayKey, -(max(1, hrDaysBack) - 1))
        var hrDayCount = 0
        for key in DayKey.keys(from: max(hrStartKey, startKey), to: todayKey) {
            guard let dayStart = DayKey.date(from: key) else { continue }
            let dayEnd = min(dayStart.addingTimeInterval(24 * 3600), windowEnd)
            guard dayEnd > dayStart else { continue }
            do {
                let samples = try await client.fetchSamples(
                    type: "heart-rate",
                    payloadKey: "heartRate",
                    valueKeys: ["beatsPerMinute", "bpm", "value"],
                    start: dayStart,
                    end: dayEnd
                )
                guard !samples.isEmpty else { continue }
                let downsampled = Self.downsampleToMinutes(samples)
                update(key) { $0.hrSamples = downsampled }
                hrDayCount += 1
            } catch {
                note("Herzfrequenz", "\(key): \(Self.describe(error))", error: true)
                break // gleicher Fehler würde sich für jeden Tag wiederholen
            }
        }
        if hrDayCount > 0 {
            note("Herzfrequenz", "\(hrDayCount) Tage Intraday")
        }

        // Ruhepuls-Fallback: 5. Perzentil der nächtlichen HF (00:00–08:00)
        for key in DayKey.keys(from: startKey, to: todayKey) {
            guard let record = days[key], record.restingHR == nil, !record.hrSamples.isEmpty,
                  let dayStart = DayKey.date(from: key) else { continue }
            let nightEnd = dayStart.addingTimeInterval(8 * 3600)
            let nightSamples = record.hrSamples.filter { $0.t < nightEnd }.map { $0.bpm }
            let basis = nightSamples.count >= 30 ? nightSamples : record.hrSamples.map { $0.bpm }
            if let p5 = Stats.percentile(basis, 0.05) {
                update(key) { $0.restingHR = p5 }
            }
        }

        // 10. Workouts
        report("Workouts laden…")
        do {
            let workouts = try await client.fetchExerciseSessions(start: windowStart, end: windowEnd)
            var byDay: [String: [Workout]] = [:]
            for workout in workouts {
                byDay[DayKey.string(from: workout.start), default: []].append(workout)
            }
            for (key, list) in byDay {
                update(key) { $0.workouts = list.sorted { $0.start < $1.start } }
            }
            note("Workouts", "\(workouts.count) Sessions")
        } catch {
            note("Workouts", Self.describe(error), error: true)
        }

        progress?(SyncProgress(message: "Fertig", fraction: 1))
        return SyncOutcome(updatedDays: days, log: log, profile: profile)
    }

    // MARK: - Helfer

    /// Gruppiert Samples nach Aufwach-Tag (Nacht-Zuordnung via +6h-Verschiebung).
    public static func groupByNight(_ samples: [SamplePoint]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for sample in samples {
            result[DayKey.nightKey(for: sample.time), default: []].append(sample.value)
        }
        return result
    }

    /// Reduziert Roh-Samples (bis zu 5-Sekunden-Auflösung) auf Minuten-Mittelwerte.
    public static func downsampleToMinutes(_ samples: [SamplePoint]) -> [HRSample] {
        var buckets: [Date: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let bucket = Date(timeIntervalSince1970: (sample.time.timeIntervalSince1970 / 60).rounded(.down) * 60)
            let existing = buckets[bucket] ?? (0, 0)
            buckets[bucket] = (existing.sum + sample.value, existing.count + 1)
        }
        return buckets
            .map { HRSample(t: $0.key, bpm: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.t < $1.t }
    }

    static func describe(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        return error.localizedDescription
    }
}

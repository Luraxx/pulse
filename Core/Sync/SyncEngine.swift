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

    /// Kompletter Sync in zwei Phasen: erst alle Tagesmetriken (schnell),
    /// dann die Intraday-Herzfrequenz (viele Requests, parallel + inkrementell).
    public func sync(
        existingDays: [String: DayRecord],
        daysBack: Int,
        hrDaysBack: Int,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async -> SyncOutcome {
        let daily = await syncDailyMetrics(existingDays: existingDays, daysBack: daysBack) { p in
            progress?(SyncProgress(message: p.message, fraction: p.fraction * 0.55))
        }
        let hr = await syncIntradayHeartRate(existingDays: daily.updatedDays, hrDaysBack: hrDaysBack) { p in
            progress?(SyncProgress(message: p.message, fraction: 0.55 + p.fraction * 0.45))
        }
        return SyncOutcome(updatedDays: hr.updatedDays, log: daily.log + hr.log, profile: daily.profile)
    }

    /// Phase 1: alle Tagesmetriken (je 1–2 Requests). Nach dieser Phase sind
    /// Recovery, Schlaf und alle Tageswerte vollständig — nur die
    /// Intraday-HF (Strain-Detail) fehlt noch.
    public func syncDailyMetrics(
        existingDays: [String: DayRecord],
        daysBack: Int,
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

        // 3. HRV (nächtlicher RMSSD). Fitbit liefert HRV je nach Gerät als
        // Sample-Strom ODER als Tagesaggregat — erst Samples, dann Tages-Fallback.
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
            if grouped.isEmpty {
                do {
                    let daily = try await client.fetchDailyValues(
                        type: "daily-heart-rate-variability",
                        payloadKey: "dailyHeartRateVariability",
                        valueKeys: ["rmssdMilliseconds", "rmssd", "milliseconds", "value"],
                        start: windowStart,
                        end: windowEnd
                    )
                    for (key, value) in daily {
                        update(key) { $0.hrvRmssd = value }
                    }
                    note("HRV", "\(daily.count) Tage (Tagesaggregat)")
                } catch {
                    note("HRV", "0 Samples; Tages-HRV nicht verfügbar: \(Self.describe(error))", error: true)
                }
            } else {
                note("HRV", "\(samples.count) Samples, \(grouped.count) Nächte")
            }
        } catch {
            note("HRV", Self.describe(error), error: true)
        }

        // 4. Atemfrequenz (Google-Health-Tagesaggregat aus dem Schlaf)
        report("Atemfrequenz laden…")
        do {
            let values = try await client.fetchDailyValues(
                type: "daily-respiratory-rate",
                payloadKey: "dailyRespiratoryRate",
                valueKeys: ["breathsPerMinute", "rate", "value"],
                start: windowStart,
                end: windowEnd
            )
            for (key, value) in values {
                update(key) { $0.respiratoryRate = value }
            }
            note("Atemfrequenz", "\(values.count) Tage")
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

        // 6. Temperatur (nächtliche Hauttemperatur-Ableitung, Tageswert)
        report("Temperatur laden…")
        do {
            let values = try await client.fetchDailyValues(
                type: "daily-sleep-temperature-derivations",
                payloadKey: "dailySleepTemperatureDerivations",
                valueKeys: ["nightlyTemperatureCelsius", "baselineTemperatureCelsius", "celsius", "value"],
                start: windowStart,
                end: windowEnd
            )
            for (key, value) in values {
                update(key) { $0.bodyTemp = value }
            }
            note("Temperatur", "\(values.count) Tage")
        } catch {
            note("Temperatur", Self.describe(error), error: true)
        }

        // 7. Ruhepuls (Tagesdatentyp; Fallback später aus Nacht-HR)
        report("Ruhepuls laden…")
        do {
            let values = try await client.fetchDailyValues(
                type: "daily-resting-heart-rate",
                payloadKey: "dailyRestingHeartRate",
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

        // 7b. VO₂max / Cardio-Fitness (Tagesdatentyp, ml/kg/min)
        report("VO₂max laden…")
        do {
            let values = try await client.fetchDailyValues(
                type: "daily-vo2-max",
                payloadKey: "dailyVo2Max",
                valueKeys: ["vo2Max", "vo2max", "cardioFitnessScore", "value"],
                start: windowStart,
                end: windowEnd
            )
            for (key, value) in values {
                update(key) { $0.vo2max = value }
            }
            note("VO₂max", "\(values.count) Tage")
        } catch {
            note("VO₂max", "\(Self.describe(error)) – Fallback über HF-Ratio aktiv", error: true)
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

        // 9. Workouts
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

    // MARK: - Phase 2: Intraday-Herzfrequenz

    /// Ist die Intraday-HF dieses Tages erledigt (→ beim Sync überspringen)?
    /// - Heute und gestern werden IMMER neu geladen (die Uhr synct oft mit
    ///   Verzögerung in die Google-Health-App).
    /// - Ältere Tage gelten als erledigt, sobald sie einmal NACH ihrem Tagesende
    ///   geprüft wurden — **auch wenn der Tag leer blieb**. Sonst würden nie
    ///   getragene Vergangenheitstage bei jedem Sync erneut abgefragt.
    public static func isIntradayComplete(_ record: DayRecord?, dayKey: String) -> Bool {
        if dayKey >= DayKey.addDays(DayKey.today(), -1) { return false }
        guard let record, let hrSyncedAt = record.hrSyncedAt,
              let dayStart = DayKey.date(from: dayKey) else { return false }
        return hrSyncedAt >= dayStart.addingTimeInterval(24 * 3600)
    }

    /// Phase 2: lädt die Intraday-HF fehlender Tage — bis zu `maxConcurrent`
    /// Tage parallel (je Tag viele paginierte Requests, deshalb der Engpass).
    public func syncIntradayHeartRate(
        existingDays: [String: DayRecord],
        hrDaysBack: Int,
        maxConcurrent: Int = 4,
        progress: (@Sendable (SyncProgress) -> Void)? = nil
    ) async -> SyncOutcome {
        var days = existingDays
        var log: [SyncLogEntry] = []
        let todayKey = DayKey.today()
        let startKey = DayKey.addDays(todayKey, -(max(1, hrDaysBack) - 1))
        let syncStamp = Date()
        let windowEnd = Date()

        let allKeys = DayKey.keys(from: startKey, to: todayKey)
        let keysToLoad = allKeys.filter { !Self.isIntradayComplete(days[$0], dayKey: $0) }
        let skipped = allKeys.count - keysToLoad.count

        guard !keysToLoad.isEmpty else {
            log.append(SyncLogEntry(metric: "Herzfrequenz", detail: "\(skipped) Tage bereits vollständig"))
            progress?(SyncProgress(message: "Fertig", fraction: 1))
            return SyncOutcome(updatedDays: days, log: log, profile: nil)
        }

        progress?(SyncProgress(message: "Herzfrequenz laden… (0/\(keysToLoad.count) Tage)", fraction: 0))

        let client = self.client
        var loaded = 0
        var failed = 0
        var done = 0
        var firstError: String?

        await withTaskGroup(of: (String, Result<[SamplePoint], Error>).self) { group in
            @Sendable func fetchDay(_ key: String) async -> (String, Result<[SamplePoint], Error>) {
                guard let dayStart = DayKey.date(from: key) else { return (key, .success([])) }
                let dayEnd = min(dayStart.addingTimeInterval(24 * 3600), windowEnd)
                guard dayEnd > dayStart else { return (key, .success([])) }
                do {
                    let samples = try await client.fetchSamples(
                        type: "heart-rate",
                        payloadKey: "heartRate",
                        valueKeys: ["beatsPerMinute", "bpm", "value"],
                        start: dayStart,
                        end: dayEnd
                    )
                    return (key, .success(samples))
                } catch {
                    return (key, .failure(error))
                }
            }

            var iterator = keysToLoad.makeIterator()
            for _ in 0..<min(maxConcurrent, keysToLoad.count) {
                if let key = iterator.next() {
                    group.addTask { await fetchDay(key) }
                }
            }
            for await (key, result) in group {
                switch result {
                case .success(let samples):
                    var record = days[key] ?? DayRecord(date: key)
                    if !samples.isEmpty {
                        record.hrSamples = Self.removeSpikes(Self.downsampleToMinutes(samples))
                        record.syncedAt = syncStamp
                        loaded += 1
                    }
                    // Auch leere Tage stempeln → vergangene, nie getragene Tage
                    // werden nicht bei jedem Sync erneut abgefragt (heute/gestern
                    // laufen ohnehin immer, siehe isIntradayComplete).
                    record.hrSyncedAt = syncStamp
                    days[key] = record
                case .failure(let error):
                    failed += 1
                    if firstError == nil { firstError = Self.describe(error) }
                }
                done += 1
                progress?(SyncProgress(
                    message: "Herzfrequenz laden… (\(done)/\(keysToLoad.count) Tage)",
                    fraction: Double(done) / Double(keysToLoad.count)
                ))
                if let key = iterator.next() {
                    group.addTask { await fetchDay(key) }
                }
            }
        }

        if loaded > 0 {
            let skipText = skipped > 0 ? ", \(skipped) übersprungen" : ""
            log.append(SyncLogEntry(metric: "Herzfrequenz", detail: "\(loaded) Tage Intraday\(skipText)"))
        } else if failed == 0 {
            log.append(SyncLogEntry(metric: "Herzfrequenz", detail: skipped > 0 ? "\(skipped) Tage bereits vollständig" : "keine neuen Daten"))
        }
        if failed > 0, let firstError {
            log.append(SyncLogEntry(metric: "Herzfrequenz", detail: "\(failed) Tag(e) fehlgeschlagen: \(firstError)", isError: true))
        }

        // Ruhepuls-Fallback: 5. Perzentil der nächtlichen HF (00:00–08:00)
        for key in allKeys {
            guard var record = days[key], record.restingHR == nil, !record.hrSamples.isEmpty,
                  let dayStart = DayKey.date(from: key) else { continue }
            let nightEnd = dayStart.addingTimeInterval(8 * 3600)
            let nightSamples = record.hrSamples.filter { $0.t < nightEnd }.map { $0.bpm }
            let basis = nightSamples.count >= 30 ? nightSamples : record.hrSamples.map { $0.bpm }
            if let p5 = Stats.percentile(basis, 0.05) {
                record.restingHR = p5
                record.syncedAt = syncStamp
                days[key] = record
            }
        }

        progress?(SyncProgress(message: "Fertig", fraction: 1))
        return SyncOutcome(updatedDays: days, log: log, profile: nil)
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

    /// Glättet isolierte Herzfrequenz-Artefakte: Ein einzelnes Sample, das
    /// gegenüber **beiden** Nachbarn um mehr als `maxJump` in dieselbe Richtung
    /// ausschlägt (physiologisch unmöglich in 1 Minute), wird durch den
    /// Nachbar-Mittelwert ersetzt. Echte Anstiege sind graduell und bleiben.
    public static func removeSpikes(_ samples: [HRSample], maxJump: Double = 40) -> [HRSample] {
        guard samples.count >= 3 else { return samples }
        var result = samples
        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1].bpm
            let cur = samples[i].bpm
            let next = samples[i + 1].bpm
            let dPrev = cur - prev
            let dNext = cur - next
            // Beide Differenzen groß und gleiches Vorzeichen → isolierte Spitze/Delle.
            if abs(dPrev) > maxJump, abs(dNext) > maxJump, dPrev * dNext > 0 {
                result[i] = HRSample(t: samples[i].t, bpm: (prev + next) / 2)
            }
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

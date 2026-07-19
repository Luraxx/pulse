import Foundation

/// Deterministischer Zufallsgenerator (xorshift64), damit der Demo-Datensatz
/// reproduzierbar ist.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Erzeugt einen plausiblen, korrelierten Demo-Datensatz (Trainingsrhythmus,
/// Erholungsdips nach harten Tagen, gelegentliche schlechte Nächte), damit die
/// App ohne Google-Verbindung ausprobiert werden kann.
public enum DemoData {
    public static func generate(daysBack: Int = 120, seed: UInt64 = 42) -> [String: DayRecord] {
        var rng = SeededRNG(seed: seed)
        var result: [String: DayRecord] = [:]
        let todayKey = DayKey.today()
        let calendar = Calendar.current

        var previousIntensity = 0.0
        var previousAlcohol = false

        for offset in stride(from: daysBack - 1, through: 0, by: -1) {
            let key = DayKey.addDays(todayKey, -offset)
            guard let dayStart = DayKey.date(from: key) else { continue }
            var record = DayRecord(date: key)

            let weekday = calendar.component(.weekday, from: dayStart) // 1=So … 7=Sa
            let intensity = trainingIntensity(weekday: weekday, rng: &rng)
            let isWeekend = weekday == 1 || weekday == 7
            let alcohol = Double.random(in: 0...1, using: &rng) < (isWeekend ? 0.20 : 0.06)

            let dayIndex = Double(daysBack - offset)
            let slowWave = sin(dayIndex / 14 * .pi) * 3.5

            // Nächtliche Recovery-Metriken (reagieren auf den Vortag)
            let hrv = Stats.clamp(
                62 + slowWave + Double.random(in: -6...6, using: &rng)
                    - previousIntensity * 11 - (previousAlcohol ? 12 : 0),
                25, 110
            )
            let rhr = Stats.clamp(
                52 - slowWave * 0.4 + Double.random(in: -2...2, using: &rng)
                    + previousIntensity * 4 + (previousAlcohol ? 5 : 0),
                42, 78
            )
            record.hrvRmssd = hrv
            record.restingHR = rhr
            record.respiratoryRate = 14.2 + Double.random(in: -0.35...0.35, using: &rng) + (previousAlcohol ? 0.9 : 0)
            let spo2 = Stats.clamp(96.8 + Double.random(in: -0.8...0.6, using: &rng), 93, 99)
            record.spo2Avg = spo2
            record.spo2Min = spo2 - Double.random(in: 1.2...2.8, using: &rng)
            record.bodyTemp = 33.9 + Double.random(in: -0.25...0.25, using: &rng) + (previousAlcohol ? 0.4 : 0)
            // Gemessene VO₂max (Cardio-Fitness): solide aktiv (~mittleres 20er
            // Fitness-Alter für die 30-jährige Demo-Person), mit saisonaler Drift.
            record.vo2max = Stats.clamp(46.0 + slowWave * 0.3 + Double.random(in: -0.5...0.5, using: &rng), 36, 52)

            // Schlaf
            let sleepImpact = previousAlcohol ? -35.0 : 0.0
            let wakeOffset = (6.8 + (isWeekend ? 0.9 : 0) + Double.random(in: -0.4...0.5, using: &rng)) * 3600
            let wake = dayStart.addingTimeInterval(wakeOffset)
            let inBedMinutes = Stats.clamp(
                444 + Double.random(in: -55...45, using: &rng) + sleepImpact - previousIntensity * 10,
                300, 560
            )
            let bed = wake.addingTimeInterval(-inBedMinutes * 60)
            let session = makeSleepSession(id: "demo-\(key)", bed: bed, wake: wake, rng: &rng)
            record.sleepSessions = [session]
            if Double.random(in: 0...1, using: &rng) < 0.06 {
                let napStart = dayStart.addingTimeInterval(14.2 * 3600)
                let napMinutes = Double.random(in: 18...40, using: &rng)
                let nap = SleepSession(
                    id: "demo-nap-\(key)",
                    start: napStart,
                    end: napStart.addingTimeInterval(napMinutes * 60),
                    minutesAsleep: napMinutes * 0.9,
                    minutesAwake: napMinutes * 0.1,
                    stages: [],
                    isMainSleep: false
                )
                record.sleepSessions.append(nap)
            }

            // Workout
            var workout: Workout?
            if intensity > 0.2 {
                let names: [String]
                switch weekday {
                case 2, 5: names = ["Intervalle", "Laufen"]
                case 3: names = ["Krafttraining", "Rad"]
                case 7: names = ["Langer Lauf", "Radtour"]
                default: names = ["Laufen", "Rad", "Krafttraining"]
                }
                let name = names[Int(rng.next() % UInt64(names.count))]
                let duration = 35 + intensity * 60 + Double.random(in: 0...20, using: &rng)
                let startHour = weekday == 7 ? 10.0 : 17.5 + Double.random(in: -1.0...1.5, using: &rng)
                let start = dayStart.addingTimeInterval(startHour * 3600)
                let maxHR = 187.0
                let avgHR = rhr + (maxHR - rhr) * (0.48 + intensity * 0.32)
                workout = Workout(
                    id: "demo-workout-\(key)",
                    name: name,
                    start: start,
                    end: start.addingTimeInterval(duration * 60),
                    averageHR: avgHR,
                    calories: duration * (6 + intensity * 6)
                )
                record.workouts = [workout!]
            }

            // Schritte
            record.steps = Int(3500 + intensity * 9000 + Double.random(in: 0...2500, using: &rng))

            // Intraday-HF (2-min-Auflösung) für die letzten 28 Tage
            if offset < 28 {
                record.hrSamples = makeHRSamples(
                    dayStart: dayStart,
                    session: session,
                    workout: workout,
                    rhr: rhr,
                    rng: &rng
                )
                record.hrSyncedAt = Date()
            }

            record.syncedAt = Date()
            result[key] = record
            previousIntensity = intensity
            previousAlcohol = alcohol
        }
        return result
    }

    private static func trainingIntensity(weekday: Int, rng: inout SeededRNG) -> Double {
        let base: Double
        switch weekday {
        case 2: base = 0.85 // Montag hart
        case 3: base = 0.55
        case 4: base = 0.25
        case 5: base = 0.80 // Donnerstag hart
        case 6: base = 0.10
        case 7: base = 0.70 // Samstag lang
        default: base = 0.0 // Sonntag Ruhetag
        }
        guard base > 0 else { return 0 }
        return Stats.clamp(base + Double.random(in: -0.15...0.15, using: &rng), 0, 1)
    }

    private static func makeSleepSession(id: String, bed: Date, wake: Date, rng: inout SeededRNG) -> SleepSession {
        var stages: [StageSpan] = []
        var cursor = bed
        var awakeMinutes = 0.0
        let totalMinutes = wake.timeIntervalSince(bed) / 60
        var elapsed = 0.0

        while cursor < wake {
            let progress = elapsed / totalMinutes
            let roll = Double.random(in: 0...1, using: &rng)
            let stage: SleepStage
            if roll < 0.05 && elapsed > 30 {
                stage = .awake
            } else if progress < 0.45 {
                stage = roll < 0.42 ? .deep : .light
            } else if progress > 0.55 {
                stage = roll < 0.40 ? .rem : .light
            } else {
                stage = .light
            }
            let length = stage == .awake
                ? Double.random(in: 2...7, using: &rng)
                : Double.random(in: 14...36, using: &rng)
            let end = min(cursor.addingTimeInterval(length * 60), wake)
            stages.append(StageSpan(stage: stage, start: cursor, end: end))
            if stage == .awake {
                awakeMinutes += end.timeIntervalSince(cursor) / 60
            }
            elapsed += end.timeIntervalSince(cursor) / 60
            cursor = end
        }

        let asleep = totalMinutes - awakeMinutes
        return SleepSession(
            id: id,
            start: bed,
            end: wake,
            minutesAsleep: asleep,
            minutesAwake: awakeMinutes,
            stages: stages,
            isMainSleep: true
        )
    }

    private static func makeHRSamples(
        dayStart: Date,
        session: SleepSession,
        workout: Workout?,
        rhr: Double,
        rng: inout SeededRNG
    ) -> [HRSample] {
        var samples: [HRSample] = []
        let now = Date()
        var minute = 0.0
        while minute < 1440 {
            let t = dayStart.addingTimeInterval(minute * 60)
            if t > now { break }

            var bpm: Double
            if t >= session.start && t < session.end {
                bpm = rhr + Double.random(in: -2...6, using: &rng)
            } else if let workout, t >= workout.start, t < workout.end, let avgHR = workout.averageHR {
                let workoutProgress = t.timeIntervalSince(workout.start) / max(60, workout.end.timeIntervalSince(workout.start))
                let ramp = min(1, workoutProgress * 4)
                bpm = rhr + (avgHR - rhr) * ramp + Double.random(in: -8...10, using: &rng)
            } else {
                bpm = rhr + 14 + Double.random(in: -6...14, using: &rng)
                // Alltagsspitzen (Treppen, Wege)
                if Double.random(in: 0...1, using: &rng) < 0.03 {
                    bpm += Double.random(in: 10...30, using: &rng)
                }
            }
            samples.append(HRSample(t: t, bpm: Stats.clamp(bpm, 40, 195)))
            minute += 2
        }
        return samples
    }
}

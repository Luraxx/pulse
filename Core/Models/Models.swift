import Foundation

// MARK: - Sleep

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case awake
    case light
    case deep
    case rem
    case unknown

    /// Maps Google Health API enums (uppercase) and Fitbit legacy values.
    public init(apiValue: String) {
        switch apiValue.uppercased() {
        case "AWAKE", "WAKE", "RESTLESS": self = .awake
        case "LIGHT", "ASLEEP": self = .light
        case "DEEP": self = .deep
        case "REM": self = .rem
        default: self = .unknown
        }
    }

    public var isAsleep: Bool {
        self == .light || self == .deep || self == .rem
    }
}

public struct StageSpan: Codable, Hashable, Sendable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var minutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

public struct SleepSession: Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var minutesAsleep: Double
    public var minutesAwake: Double
    public var stages: [StageSpan]
    public var isMainSleep: Bool

    public init(
        id: String,
        start: Date,
        end: Date,
        minutesAsleep: Double,
        minutesAwake: Double,
        stages: [StageSpan] = [],
        isMainSleep: Bool = true
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.minutesAsleep = minutesAsleep
        self.minutesAwake = minutesAwake
        self.stages = stages
        self.isMainSleep = isMainSleep
    }

    public var minutesInBed: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }

    /// Sleep efficiency in percent (time asleep / time in bed).
    public var efficiency: Double? {
        guard minutesInBed > 0 else { return nil }
        return min(100, minutesAsleep / minutesInBed * 100)
    }

    public func minutes(in stage: SleepStage) -> Double {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    public var stageMinutes: [SleepStage: Double] {
        var result: [SleepStage: Double] = [:]
        for span in stages {
            result[span.stage, default: 0] += span.minutes
        }
        return result
    }
}

// MARK: - Heart rate

public struct HRSample: Codable, Hashable, Sendable {
    /// Timestamp (minute resolution after downsampling)
    public var t: Date
    public var bpm: Double

    public init(t: Date, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

// MARK: - Workouts

public struct Workout: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var start: Date
    public var end: Date
    public var averageHR: Double?
    public var calories: Double?
    /// Computed strain value (0–21), set by the StrainEngine.
    public var strain: Double?

    public init(
        id: String,
        name: String,
        start: Date,
        end: Date,
        averageHR: Double? = nil,
        calories: Double? = nil,
        strain: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.averageHR = averageHR
        self.calories = calories
        self.strain = strain
    }

    public var durationMinutes: Double {
        max(0, end.timeIntervalSince(start) / 60)
    }
}

// MARK: - Profile

/// Biological sex — needed because the age reference values (VO₂max, HRV,
/// resting HR) are sex-specific. "unspecified" uses averaged curves.
public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case male
    case female
    case unspecified

    /// Maps Google/Fitbit enums ("MALE"/"FEMALE", "male"…).
    public init(apiValue: String?) {
        switch apiValue?.uppercased() {
        case "MALE", "M": self = .male
        case "FEMALE", "F": self = .female
        default: self = .unspecified
        }
    }

    public var label: String {
        switch self {
        case .male: return "Männlich"
        case .female: return "Weiblich"
        case .unspecified: return "Keine Angabe"
        }
    }
}

public struct UserProfile: Codable, Sendable {
    public var displayName: String?
    /// Birthday as "yyyy-MM-dd", if the API provides it.
    public var birthday: String?
    public var sex: BiologicalSex

    public init(displayName: String? = nil, birthday: String? = nil, sex: BiologicalSex = .unspecified) {
        self.displayName = displayName
        self.birthday = birthday
        self.sex = sex
    }

    public var age: Int? {
        guard let birthday, let date = DayKey.date(from: birthday) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year
        return years
    }
}

// MARK: - Daily record

/// All metrics of a calendar day. Overnight values (HRV, respiratory rate, SpO2,
/// temperature) are assigned to the day of waking up.
public struct DayRecord: Codable, Sendable {
    public var date: String // "yyyy-MM-dd"

    // Overnight recovery metrics
    public var hrvRmssd: Double?          // ms, overnight average
    public var restingHR: Double?         // beats/min
    public var respiratoryRate: Double?   // breaths/min
    public var spo2Avg: Double?           // %
    public var spo2Min: Double?           // %
    public var bodyTemp: Double?          // °C (overnight skin/body temperature)
    /// Cardio fitness / VO₂max (ml/kg/min) — measured by Google Health
    /// daily value (daily-vo2-max), if available.
    public var vo2max: Double?

    // Activity
    public var steps: Int?
    public var sleepSessions: [SleepSession]
    public var workouts: [Workout]
    /// Intraday heart rate, reduced to 1-minute resolution.
    public var hrSamples: [HRSample]

    public var syncedAt: Date?
    /// Time of the last intraday HR load. If it is AFTER the end of the day,
    /// the day is complete and is skipped on the next sync.
    public var hrSyncedAt: Date?

    public init(date: String) {
        self.date = date
        self.sleepSessions = []
        self.workouts = []
        self.hrSamples = []
    }

    /// Main sleep = session marked as such, otherwise the longest.
    public var mainSleep: SleepSession? {
        if let flagged = sleepSessions.first(where: { $0.isMainSleep }) {
            return flagged
        }
        return sleepSessions.max(by: { $0.minutesAsleep < $1.minutesAsleep })
    }

    public var naps: [SleepSession] {
        guard let main = mainSleep else { return [] }
        return sleepSessions.filter { $0.id != main.id }
    }

    public var totalSleepMinutes: Double {
        sleepSessions.reduce(0) { $0 + $1.minutesAsleep }
    }
}

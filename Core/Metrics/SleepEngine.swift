import Foundation

public struct SleepEngineConfig: Sendable {
    /// Base sleep need in minutes (default: 7 h 36 min, like the Whoop default).
    public var baselineNeedMinutes: Double
    /// Share of sleep debt additionally required per night.
    public var debtRepayFraction: Double
    /// Upper limit of accumulated sleep debt.
    public var maxDebtMinutes: Double
    /// Maximum debt INCREASE per night. Prevents a single
    /// disaster or artifact night (e.g. a short setup session on the
    /// first day) from maxing out the debt in one go.
    public var maxDebtGainPerNightMinutes: Double
    /// Maximum need increase from high previous-day strain.
    public var strainNeedBoostMaxMinutes: Double

    public init(
        baselineNeedMinutes: Double = 456,
        debtRepayFraction: Double = 0.30,
        maxDebtMinutes: Double = 300,
        maxDebtGainPerNightMinutes: Double = 180,
        strainNeedBoostMaxMinutes: Double = 45
    ) {
        self.baselineNeedMinutes = baselineNeedMinutes
        self.debtRepayFraction = debtRepayFraction
        self.maxDebtMinutes = maxDebtMinutes
        self.maxDebtGainPerNightMinutes = maxDebtGainPerNightMinutes
        self.strainNeedBoostMaxMinutes = strainNeedBoostMaxMinutes
    }
}

public struct SleepAnalysis: Sendable {
    public let dateKey: String
    public let sleptMinutes: Double
    public let napMinutes: Double
    public let needMinutes: Double
    /// Sleep performance 0–100 (time slept / need).
    public let performance: Double
    /// Sleep debt AFTER this night.
    public let debtAfterMinutes: Double
    /// Consistency of bed/wake times (0–100), nil without history.
    public let consistency: Double?
    public let efficiency: Double?
    public let stageMinutes: [SleepStage: Double]
    public let bedTime: Date?
    public let wakeTime: Date?
    public let hasData: Bool

    public var restorativeMinutes: Double {
        (stageMinutes[.deep] ?? 0) + (stageMinutes[.rem] ?? 0)
    }
}

/// Recommendation for the coming night.
public struct BedtimeRecommendation: Sendable {
    /// Projected sleep need tonight (minutes).
    public let projectedNeedMinutes: Double
    /// Usual wake time as minutes since midnight (nil without history).
    public let habitualWakeMinutes: Double?
    /// Recommended bedtime as minutes since midnight (nil without history).
    public let recommendedBedtimeMinutes: Double?
    /// Current sleep debt (minutes) the projection is based on.
    public let debtMinutes: Double
}

public enum SleepEngine {
    /// Recommendation for the coming night: projected need (from sleep debt
    /// and today's strain) and – from the usual wake time – the time
    /// to go to bed for it.
    public static func bedtimeRecommendation(
        currentDebtMinutes: Double,
        strainToday: Double,
        recentWakeTimes: [Date],
        config: SleepEngineConfig = SleepEngineConfig()
    ) -> BedtimeRecommendation {
        let strainBoost = Stats.clamp((strainToday - 8) / 13, 0, 1) * config.strainNeedBoostMaxMinutes
        var need = config.baselineNeedMinutes + currentDebtMinutes * config.debtRepayFraction + strainBoost
        need = Stats.clamp(need, config.baselineNeedMinutes - 30, config.baselineNeedMinutes + 150)

        guard !recentWakeTimes.isEmpty else {
            return BedtimeRecommendation(
                projectedNeedMinutes: need,
                habitualWakeMinutes: nil,
                recommendedBedtimeMinutes: nil,
                debtMinutes: currentDebtMinutes
            )
        }

        // Wake times are in the morning (no midnight crossing) → simple mean.
        let wakeMinutes = recentWakeTimes.map { clockMinutes(of: $0) }
        let habitualWake = Stats.mean(wakeMinutes)
        let bedtime = ((habitualWake - need).truncatingRemainder(dividingBy: 1440) + 1440)
            .truncatingRemainder(dividingBy: 1440)

        return BedtimeRecommendation(
            projectedNeedMinutes: need,
            habitualWakeMinutes: habitualWake,
            recommendedBedtimeMinutes: bedtime,
            debtMinutes: currentDebtMinutes
        )
    }

    /// Minutes since midnight (0…1439).
    static func clockMinutes(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Analyzes all days chronologically and carries sleep debt and
    /// consistency history across the whole time series.
    /// `strainByDay` provides the daily strain (for the next night's need surcharge).
    public static func analyze(
        days: [String: DayRecord],
        config: SleepEngineConfig = SleepEngineConfig(),
        strainByDay: [String: Double] = [:]
    ) -> [String: SleepAnalysis] {
        let keys = days.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return [:] }

        var result: [String: SleepAnalysis] = [:]
        var debt: Double = 0
        var recentBedWake: [(bed: Double, wake: Double)] = []

        for key in DayKey.keys(from: first, to: last) {
            let record = days[key]
            let sessions = record?.sleepSessions ?? []
            let main = record?.mainSleep
            let slept = sessions.reduce(0) { $0 + $1.minutesAsleep }
            let napMinutes = slept - (main?.minutesAsleep ?? 0)
            let hasData = main != nil && slept > 0

            let previousStrain = strainByDay[DayKey.addDays(key, -1)] ?? 0
            let strainBoost = Stats.clamp((previousStrain - 8) / 13, 0, 1) * config.strainNeedBoostMaxMinutes
            var need = config.baselineNeedMinutes + debt * config.debtRepayFraction + strainBoost
            need = Stats.clamp(need, config.baselineNeedMinutes - 30, config.baselineNeedMinutes + 150)

            let performance = hasData ? min(100, slept / need * 100) : 0

            if hasData {
                // Debt is booked against base + strain surcharge, NOT
                // against the displayed need: that one includes debt
                // repayment, and measured against it the debt would compound —
                // someone sleeping exactly their base would never get back down
                // from the cap. (Whoop logic: what is slept ABOVE
                // the baseline counts as repaid.)
                let structuralNeed = config.baselineNeedMinutes + strainBoost
                let delta = min(structuralNeed - slept, config.maxDebtGainPerNightMinutes)
                debt = Stats.clamp(debt + delta, 0, config.maxDebtMinutes)
            }

            var consistency: Double?
            if let main {
                let bed = shiftedMinutes(of: main.start)
                let wake = shiftedMinutes(of: main.end)
                if !recentBedWake.isEmpty {
                    let deviations = recentBedWake.map { entry in
                        (circularDiff(entry.bed, bed) + circularDiff(entry.wake, wake)) / 2
                    }
                    let avgDev = Stats.mean(deviations)
                    consistency = Stats.clamp(100 - avgDev / 90 * 100, 0, 100)
                }
                recentBedWake.append((bed, wake))
                if recentBedWake.count > 4 {
                    recentBedWake.removeFirst()
                }
            }

            var stageMinutes = main?.stageMinutes ?? [:]
            if stageMinutes.isEmpty, let main {
                stageMinutes = [.light: main.minutesAsleep]
            }

            result[key] = SleepAnalysis(
                dateKey: key,
                sleptMinutes: slept,
                napMinutes: max(0, napMinutes),
                needMinutes: need,
                performance: performance,
                debtAfterMinutes: debt,
                consistency: consistency,
                efficiency: main?.efficiency,
                stageMinutes: stageMinutes,
                bedTime: main?.start,
                wakeTime: main?.end,
                hasData: hasData
            )
        }
        return result
    }

    /// Minutes since 12:00 (shifted so times around midnight stay linear).
    private static func shiftedMinutes(of date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        return (minutes + 720).truncatingRemainder(dividingBy: 1440)
    }

    private static func circularDiff(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        return min(diff, 1440 - diff)
    }
}

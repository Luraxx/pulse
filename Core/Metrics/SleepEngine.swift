import Foundation

public struct SleepEngineConfig: Sendable {
    /// Basis-Schlafbedarf in Minuten (Standard: 7 h 36 min, wie Whoop-Default).
    public var baselineNeedMinutes: Double
    /// Anteil der Schlafschuld, der pro Nacht zusätzlich eingefordert wird.
    public var debtRepayFraction: Double
    /// Obergrenze der akkumulierten Schlafschuld.
    public var maxDebtMinutes: Double
    /// Maximaler Bedarfs-Aufschlag durch hohen Vortages-Strain.
    public var strainNeedBoostMaxMinutes: Double

    public init(
        baselineNeedMinutes: Double = 456,
        debtRepayFraction: Double = 0.30,
        maxDebtMinutes: Double = 300,
        strainNeedBoostMaxMinutes: Double = 45
    ) {
        self.baselineNeedMinutes = baselineNeedMinutes
        self.debtRepayFraction = debtRepayFraction
        self.maxDebtMinutes = maxDebtMinutes
        self.strainNeedBoostMaxMinutes = strainNeedBoostMaxMinutes
    }
}

public struct SleepAnalysis: Sendable {
    public let dateKey: String
    public let sleptMinutes: Double
    public let napMinutes: Double
    public let needMinutes: Double
    /// Schlafperformance 0–100 (geschlafene Zeit / Bedarf).
    public let performance: Double
    /// Schlafschuld NACH dieser Nacht.
    public let debtAfterMinutes: Double
    /// Konsistenz der Zubettgeh-/Aufwachzeiten (0–100), nil ohne Historie.
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

public enum SleepEngine {
    /// Analysiert alle Tage chronologisch und führt Schlafschuld sowie
    /// Konsistenz-Historie über die gesamte Zeitreihe.
    /// `strainByDay` liefert den Tages-Strain (für den Bedarfs-Aufschlag der Folgenacht).
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
                debt = Stats.clamp(debt + (need - slept), 0, config.maxDebtMinutes)
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

    /// Minuten seit 12:00 Uhr (verschoben, damit Zeiten um Mitternacht linear bleiben).
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

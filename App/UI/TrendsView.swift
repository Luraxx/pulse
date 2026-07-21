import SwiftUI

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var range = 30

    private var today: String { DayKey.today() }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Zeitraum", selection: $range) {
                            Text(model.loc("7 Tage", "7 days")).tag(7)
                            Text(model.loc("30 Tage", "30 days")).tag(30)
                            Text(model.loc("90 Tage", "90 days")).tag(90)
                        }
                        .pickerStyle(.segmented)

                        if model.hasData {
                            summaryCard
                            recoveryStrainCard
                            sleepCard
                            hrvCard
                            rhrCard
                            journalInsightsCard
                        } else {
                            EmptyDataHint(text: model.loc("Keine Daten vorhanden.", "No data available."))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Trends")
        }
    }

    private var journalInsightsCard: some View {
        SectionCard(model.loc("Journal-Korrelationen", "Journal correlations")) {
            let ready = model.recoveryDayCount >= JournalEngine.assessmentMinRecoveryDays
            if model.journalInsights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EmptyDataHint(text: model.loc("Hake im Tab Heute deine Faktoren ab. Ein Zusammenhang erscheint, sobald ein Faktor an mind. 5 Tagen an- UND 5 Tagen abgehakt war.", "Check off factors in the Today tab. A correlation appears once a factor was checked on at least 5 days AND unchecked on 5 days."))
                    if !ready {
                        assessmentProgress
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(model.journalInsights) { insight in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Label(insight.factor.label(model.language), systemImage: insight.factor.symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(insight.confidence == .solid ? model.loc("belastbar", "solid") : model.loc("Tendenz", "trend"))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(insight.confidence == .solid
                                        ? Theme.green.opacity(0.16)
                                        : Theme.cardElevated))
                                    .foregroundStyle(insight.confidence == .solid ? Theme.green : Theme.textSecondary)
                                Spacer()
                                Text(String(format: "%+.0f", insight.delta))
                                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.bold))
                                    .foregroundStyle(insight.delta < 0 ? Theme.red : Theme.green)
                            }
                            Text(model.loc("Ø Recovery danach: \(Int(insight.avgWith.rounded())) % mit · \(Int(insight.avgWithout.rounded())) % ohne (\(insight.daysWith)/\(insight.daysWithout) Tage)", "Avg recovery after: \(Int(insight.avgWith.rounded())) % with · \(Int(insight.avgWithout.rounded())) % without (\(insight.daysWith)/\(insight.daysWithout) days)"))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if !ready {
                        assessmentProgress
                    }
                    Text(model.loc("Differenz in Recovery-Punkten am Folgetag, stärkster Effekt zuerst. Belastbar heißt: Differenz größer als das Doppelte ihres Standardfehlers. Korrelation, kein Beweis.", "Difference in next-day recovery points, strongest effect first. Solid means: difference exceeds twice its standard error. Correlation, not proof."))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var assessmentProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.loc("Monats-Auswertung ab \(JournalEngine.assessmentMinRecoveryDays) Recovery-Tagen – aktuell \(min(model.recoveryDayCount, JournalEngine.assessmentMinRecoveryDays))/\(JournalEngine.assessmentMinRecoveryDays).", "Monthly assessment from \(JournalEngine.assessmentMinRecoveryDays) recovery days – currently \(min(model.recoveryDayCount, JournalEngine.assessmentMinRecoveryDays))/\(JournalEngine.assessmentMinRecoveryDays)."))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            ProgressView(
                value: Double(min(model.recoveryDayCount, JournalEngine.assessmentMinRecoveryDays)),
                total: Double(JournalEngine.assessmentMinRecoveryDays)
            )
            .tint(Theme.teal)
        }
    }

    // MARK: - Datenreihen

    /// Ab 90 Tagen werden alle Charts auf Wochenmittel aggregiert —
    /// 90 Tagesbalken auf Handybreite sind nicht lesbar.
    private var isWeekly: Bool { range >= 90 }

    private func adaptive(_ raw: [(key: String, value: Double)]) -> [TrendPoint] {
        trendPoints(isWeekly ? TrendMath.weeklyMean(raw) : raw)
    }

    private var rawRecovery: [(key: String, value: Double)] {
        model.trend(range, endingAt: today) { record in
            model.recovery(for: record.date).map { Double($0.score) }
        }
    }

    private var rawStrain: [(key: String, value: Double)] {
        model.trend(range, endingAt: today) { record in
            model.strain(for: record.date)?.strain
        }
    }

    private var rawSleep: [(key: String, value: Double)] {
        model.trend(range, endingAt: today) { record in
            let analysis = model.sleep(for: record.date)
            return (analysis?.hasData == true) ? analysis?.sleptMinutes : nil
        }
    }

    private var rawHrv: [(key: String, value: Double)] {
        model.trend(range, endingAt: today) { $0.hrvRmssd }
    }

    private var recoveryPoints: [TrendPoint] { adaptive(rawRecovery) }
    private var strainPoints: [TrendPoint] { adaptive(rawStrain) }
    private var sleepPoints: [TrendPoint] { adaptive(rawSleep) }

    private var needPoints: [TrendPoint] {
        adaptive(model.trend(range, endingAt: today) { record in
            model.sleep(for: record.date)?.needMinutes
        })
    }

    private var hrvPoints: [TrendPoint] { adaptive(rawHrv) }

    private var rhrPoints: [TrendPoint] {
        adaptive(model.trend(range, endingAt: today) { $0.restingHR })
    }

    /// Kleine Fußnote unter Wochen-Charts.
    @ViewBuilder
    private var weeklyNote: some View {
        if isWeekly {
            Text(model.loc("Ein Punkt = Wochenmittel", "One point = weekly average"))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
        }
    }

    // MARK: - Karten

    private var summaryCard: some View {
        SectionCard(model.loc("Durchschnitt (\(range) Tage)", "Average (\(range) days)")) {
            HStack(spacing: 12) {
                StatCell(
                    label: "Recovery",
                    value: average(rawRecovery).map { "\(Int($0.rounded())) %" } ?? "–",
                    color: average(rawRecovery).map { Theme.recoveryColor(score: Int($0)) } ?? Theme.textPrimary
                )
                StatCell(
                    label: "Strain",
                    value: average(rawStrain).map { String(format: "%.1f", $0) } ?? "–",
                    color: Theme.strainBlue
                )
                StatCell(
                    label: model.loc("Schlaf", "Sleep"),
                    value: average(rawSleep).map { "\(Fmt.hm($0)) h" } ?? "–",
                    color: Theme.sleepPurple
                )
                StatCell(
                    label: "HRV",
                    value: average(rawHrv).map { "\(Int($0.rounded())) ms" } ?? "–",
                    color: Theme.teal
                )
            }
        }
    }

    private func average(_ pairs: [(key: String, value: Double)]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        return pairs.reduce(0) { $0 + $1.value } / Double(pairs.count)
    }

    private var recoveryStrainCard: some View {
        SectionCard("Recovery vs. Strain") {
            if recoveryPoints.count >= 2 {
                if range == 30 {
                    // Tageswerte gedimmt, Trend über 7-Tage-Durchschnittslinien.
                    RecoveryStrainChart(
                        recovery: recoveryPoints,
                        strain: trendPoints(TrendMath.movingAverage(rawStrain, window: 7)),
                        recoveryTrend: trendPoints(TrendMath.movingAverage(rawRecovery, window: 7)),
                        barOpacity: 0.22,
                        showStrainSymbols: false,
                        aggregationNote: model.loc("Linien = 7-Tage-Schnitt", "Lines = 7-day average")
                    )
                } else if isWeekly {
                    RecoveryStrainChart(
                        recovery: recoveryPoints,
                        strain: strainPoints,
                        aggregationNote: model.loc("Wochenmittel", "Weekly average")
                    )
                } else {
                    RecoveryStrainChart(recovery: recoveryPoints, strain: strainPoints)
                }
                Text(model.loc("Ideal: hohe Recovery an Tagen vor hohem Strain. Dauerhaft hoher Strain bei niedriger Recovery deutet auf Übertraining hin.", "Ideal: high recovery on days before high strain. Persistently high strain with low recovery suggests overtraining."))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige Tage.", "Not enough days yet."))
            }
        }
    }

    private var sleepCard: some View {
        SectionCard(model.loc("Schlafdauer vs. Bedarf", "Sleep vs. need")) {
            if sleepPoints.count >= 2 {
                SleepTrendChart(slept: sleepPoints, need: needPoints)
                weeklyNote
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige Nächte.", "Not enough nights yet."))
            }
        }
    }

    /// Letzter Tages-Key mit Recovery — bei Wochenmitteln zeigt der letzte
    /// Chart-Punkt auf einen Montag, der selbst keine Recovery haben muss.
    private var latestRecoveryKey: String {
        rawRecovery.last?.key ?? today
    }

    private var hrvCard: some View {
        SectionCard("HRV") {
            if hrvPoints.count >= 2 {
                BaselineLineChart(
                    points: hrvPoints,
                    baseline: model.recovery(for: latestRecoveryKey)?.hrvBaseline,
                    color: Theme.teal,
                    isLogBaseline: true
                )
                weeklyNote
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige HRV-Werte.", "Not enough HRV values yet."))
            }
        }
    }

    private var rhrCard: some View {
        SectionCard(model.loc("Ruhepuls", "Resting HR")) {
            if rhrPoints.count >= 2 {
                BaselineLineChart(
                    points: rhrPoints,
                    baseline: model.recovery(for: latestRecoveryKey)?.rhrBaseline,
                    color: Theme.red
                )
                weeklyNote
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige Ruhepuls-Werte.", "Not enough resting HR values yet."))
            }
        }
    }
}

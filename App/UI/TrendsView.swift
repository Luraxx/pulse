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
                            Text("7 Tage").tag(7)
                            Text("30 Tage").tag(30)
                            Text("90 Tage").tag(90)
                        }
                        .pickerStyle(.segmented)

                        if model.hasData {
                            summaryCard
                            recoveryStrainCard
                            sleepCard
                            hrvCard
                            rhrCard
                        } else {
                            EmptyDataHint(text: "Keine Daten vorhanden.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Trends")
        }
    }

    // MARK: - Datenreihen

    private var recoveryPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { record in
            model.recovery(for: record.date).map { Double($0.score) }
        })
    }

    private var strainPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { record in
            model.strain(for: record.date)?.strain
        })
    }

    private var sleepPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { record in
            let analysis = model.sleep(for: record.date)
            return (analysis?.hasData == true) ? analysis?.sleptMinutes : nil
        })
    }

    private var needPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { record in
            model.sleep(for: record.date)?.needMinutes
        })
    }

    private var hrvPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { $0.hrvRmssd })
    }

    private var rhrPoints: [TrendPoint] {
        trendPoints(model.trend(range, endingAt: today) { $0.restingHR })
    }

    // MARK: - Karten

    private var summaryCard: some View {
        SectionCard("Durchschnitt (\(range) Tage)") {
            HStack(spacing: 12) {
                StatCell(
                    label: "Recovery",
                    value: average(recoveryPoints).map { "\(Int($0.rounded())) %" } ?? "–",
                    color: average(recoveryPoints).map { Theme.recoveryColor(score: Int($0)) } ?? Theme.textPrimary
                )
                StatCell(
                    label: "Strain",
                    value: average(strainPoints).map { String(format: "%.1f", $0) } ?? "–",
                    color: Theme.strainBlue
                )
                StatCell(
                    label: "Schlaf",
                    value: average(sleepPoints).map { "\(Fmt.hm($0)) h" } ?? "–",
                    color: Theme.sleepPurple
                )
                StatCell(
                    label: "HRV",
                    value: average(hrvPoints).map { "\(Int($0.rounded())) ms" } ?? "–",
                    color: Theme.teal
                )
            }
        }
    }

    private func average(_ points: [TrendPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }

    private var recoveryStrainCard: some View {
        SectionCard("Recovery vs. Strain") {
            if recoveryPoints.count >= 2 {
                RecoveryStrainChart(recovery: recoveryPoints, strain: strainPoints)
                Text("Ideal: hohe Recovery an Tagen vor hohem Strain. Dauerhaft hoher Strain bei niedriger Recovery deutet auf Übertraining hin.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Noch zu wenige Tage.")
            }
        }
    }

    private var sleepCard: some View {
        SectionCard("Schlafdauer vs. Bedarf") {
            if sleepPoints.count >= 2 {
                SleepTrendChart(slept: sleepPoints, need: needPoints)
            } else {
                EmptyDataHint(text: "Noch zu wenige Nächte.")
            }
        }
    }

    private var hrvCard: some View {
        SectionCard("HRV") {
            if hrvPoints.count >= 2 {
                BaselineLineChart(
                    points: hrvPoints,
                    baseline: model.recovery(for: hrvPoints.last?.key ?? today)?.hrvBaseline,
                    color: Theme.teal,
                    isLogBaseline: true
                )
            } else {
                EmptyDataHint(text: "Noch zu wenige HRV-Werte.")
            }
        }
    }

    private var rhrCard: some View {
        SectionCard("Ruhepuls") {
            if rhrPoints.count >= 2 {
                BaselineLineChart(
                    points: rhrPoints,
                    baseline: model.recovery(for: rhrPoints.last?.key ?? today)?.rhrBaseline,
                    color: Theme.red
                )
            } else {
                EmptyDataHint(text: "Noch zu wenige Ruhepuls-Werte.")
            }
        }
    }
}

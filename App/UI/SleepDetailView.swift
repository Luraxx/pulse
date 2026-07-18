import SwiftUI

struct SleepDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let sleep = model.sleep(for: model.selectedDayKey), sleep.hasData {
                        heroCard(sleep)
                        statsCard(sleep)
                        if let session = model.selectedRecord?.mainSleep, !session.stages.isEmpty {
                            SectionCard("Schlafphasen") {
                                StagesTimelineView(session: session)
                            }
                            SectionCard("Verteilung") {
                                StageDistributionView(stageMinutes: sleep.stageMinutes)
                            }
                        }
                        napsCard
                        trendCard
                    } else {
                        EmptyDataHint(text: "Kein Schlaf für diesen Tag erfasst.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Schlaf")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(_ sleep: SleepAnalysis) -> some View {
        SectionCard {
            HStack(spacing: 20) {
                RingGauge(
                    progress: sleep.performance / 100,
                    color: Theme.sleepPurple,
                    lineWidth: 14
                ) {
                    VStack(spacing: 0) {
                        Text("\(Int(sleep.performance.rounded()))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("%")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.hm(sleep.sleptMinutes)) h")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("von \(Fmt.hm(sleep.needMinutes)) h Bedarf")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let bed = sleep.bedTime, let wake = sleep.wakeTime {
                        Label("\(Fmt.clock(bed)) – \(Fmt.clock(wake)) Uhr", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if sleep.napMinutes > 1 {
                        Label("\(Int(sleep.napMinutes.rounded())) min Nickerchen", systemImage: "powersleep")
                            .font(.caption)
                            .foregroundStyle(Theme.teal)
                    }
                }
            }
        }
    }

    private func statsCard(_ sleep: SleepAnalysis) -> some View {
        SectionCard("Kennzahlen") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    StatCell(
                        label: "Schlafschuld",
                        value: "\(Fmt.hm(sleep.debtAfterMinutes)) h",
                        color: sleep.debtAfterMinutes > 60 ? Theme.orange : Theme.textPrimary
                    )
                    StatCell(
                        label: "Effizienz",
                        value: sleep.efficiency.map { "\(Int($0.rounded())) %" } ?? "–"
                    )
                    StatCell(
                        label: "Konsistenz",
                        value: sleep.consistency.map { "\(Int($0.rounded())) %" } ?? "–"
                    )
                }
                HStack(spacing: 12) {
                    StatCell(
                        label: "Erholsam (Tief + REM)",
                        value: "\(Fmt.hm(sleep.restorativeMinutes)) h",
                        color: Theme.sleepPurple
                    )
                    StatCell(
                        label: "Tiefschlaf",
                        value: "\(Fmt.hm(sleep.stageMinutes[.deep] ?? 0)) h"
                    )
                    StatCell(
                        label: "REM",
                        value: "\(Fmt.hm(sleep.stageMinutes[.rem] ?? 0)) h"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var napsCard: some View {
        if let record = model.selectedRecord, !record.naps.isEmpty {
            SectionCard("Nickerchen") {
                VStack(spacing: 8) {
                    ForEach(record.naps, id: \.id) { nap in
                        HStack {
                            Image(systemName: "powersleep")
                                .foregroundStyle(Theme.teal)
                            Text("\(Fmt.clock(nap.start)) – \(Fmt.clock(nap.end)) Uhr")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int(nap.minutesAsleep.rounded())) min")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        SectionCard("Letzte 14 Nächte") {
            let slept = trendPoints(model.trend(14) { record in
                model.sleep(for: record.date)?.hasData == true ? model.sleep(for: record.date)?.sleptMinutes : nil
            })
            let need = trendPoints(model.trend(14) { record in
                model.sleep(for: record.date)?.needMinutes
            })
            if slept.count >= 2 {
                SleepTrendChart(slept: slept, need: need)
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.sleepPurple).frame(width: 10, height: 10)
                        Text("Geschlafen")
                    }
                    HStack(spacing: 5) {
                        Capsule().fill(.white.opacity(0.7)).frame(width: 12, height: 2)
                        Text("Bedarf")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Noch zu wenige Nächte für den Trend.")
            }
        }
    }
}

import SwiftUI

struct StrainDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let strain = model.strain(for: model.selectedDayKey) {
                        heroCard(strain)
                        SectionCard("Zeit in Intensitätszonen") {
                            if strain.zoneMinutes.reduce(0, +) > 0 {
                                ZoneBarsView(zoneMinutes: strain.zoneMinutes)
                            } else {
                                EmptyDataHint(text: "Keine Belastungszeit oberhalb der Grundintensität.")
                            }
                        }
                        hrCard
                        workoutsCard
                        trendCard
                    } else {
                        EmptyDataHint(text: "Keine Belastungsdaten für diesen Tag.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Belastung")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(_ strain: StrainResult) -> some View {
        SectionCard {
            VStack(spacing: 8) {
                ArcGauge(
                    fraction: strain.strain / 21,
                    color: Theme.strainBlue,
                    lineWidth: 16
                ) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", strain.strain))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Strain von 21")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)

                HStack(spacing: 20) {
                    if let avg = strain.avgHR {
                        StatCell(label: "Ø Puls", value: "\(Int(avg.rounded()))")
                    }
                    if let peak = strain.peakHR {
                        StatCell(label: "Max. Puls", value: "\(Int(peak.rounded()))")
                    }
                    StatCell(label: "Aktive Last", value: String(format: "%.0f", strain.rawLoad))
                }

                Text(strainText(strain.strain))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func strainText(_ value: Double) -> String {
        switch value {
        case ..<6: return "Leichter Tag – gut für Erholung."
        case ..<10: return "Moderate Belastung – Alltag mit etwas Aktivität."
        case ..<14: return "Solides Training – achte heute Abend auf Schlaf."
        case ..<18: return "Harte Belastung – dein Schlafbedarf steigt spürbar."
        default: return "Maximale Belastung – plane aktiv Erholung ein."
        }
    }

    @ViewBuilder
    private var hrCard: some View {
        if let record = model.selectedRecord, !record.hrSamples.isEmpty {
            SectionCard("Herzfrequenz-Tagesverlauf") {
                HRDayChart(samples: record.hrSamples)
            }
        }
    }

    @ViewBuilder
    private var workoutsCard: some View {
        if let record = model.selectedRecord, !record.workouts.isEmpty {
            SectionCard("Workouts") {
                VStack(spacing: 10) {
                    ForEach(record.workouts, id: \.id) { workout in
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run")
                                .font(.title3)
                                .foregroundStyle(Theme.strainBlue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(Fmt.clock(workout.start)) Uhr · \(Int(workout.durationMinutes.rounded())) min"
                                     + (workout.averageHR.map { " · Ø \(Int($0.rounded()))" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if let strain = workout.strain {
                                VStack(spacing: 0) {
                                    Text(String(format: "%.1f", strain))
                                        .font(.system(.title3, design: .rounded).weight(.bold))
                                        .foregroundStyle(Theme.strainBlue)
                                    Text("Strain")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        SectionCard("Strain – letzte 14 Tage") {
            let points = trendPoints(model.trend(14) { record in
                model.strain(for: record.date)?.strain
            })
            if points.count >= 2 {
                StrainLineChart(points: points)
            } else {
                EmptyDataHint(text: "Noch zu wenige Tage für den Trend.")
            }
        }
    }
}

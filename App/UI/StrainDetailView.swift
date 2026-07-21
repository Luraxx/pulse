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
                        zonesCard(strain)
                        hrCard
                        workoutsCard
                        trendCard
                    } else {
                        EmptyDataHint(text: model.loc("Keine Belastungsdaten für diesen Tag.", "No strain data for this day."))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(model.loc("Belastung", "Strain"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Belastungsziel des Tages aus der Recovery (Whoop-artiger Ziel-Strich).
    private var targetStrain: Double? {
        model.recovery(for: model.selectedDayKey).map {
            StrainEngine.targetStrain(forRecovery: $0.score)
        }
    }

    private func heroCard(_ strain: StrainResult) -> some View {
        SectionCard {
            VStack(spacing: 8) {
                ArcGauge(
                    fraction: strain.strain / 21,
                    color: Theme.strainBlue,
                    lineWidth: 16,
                    marker: targetStrain.map { $0 / 21 }
                ) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", strain.strain))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(model.loc("Strain von 21", "Strain of 21"))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        if let target = targetStrain {
                            Text(model.loc("Ziel \(String(format: "%.1f", target))", "Target \(String(format: "%.1f", target))"))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        }
                    }
                }
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)

                HStack(spacing: 20) {
                    if let avg = strain.avgHR {
                        StatCell(label: model.loc("Ø Puls", "Avg HR"), value: "\(Int(avg.rounded()))")
                    }
                    if let peak = strain.peakHR {
                        StatCell(label: model.loc("Max. Puls", "Max HR"), value: "\(Int(peak.rounded()))")
                    }
                    StatCell(label: model.loc("Aktive Last", "Active load"), value: String(format: "%.0f", strain.rawLoad))
                }

                Text(targetText(strain))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Einordnung relativ zum Tagesziel (falls vorhanden), sonst absolute Skala.
    private func targetText(_ strain: StrainResult) -> String {
        guard let target = targetStrain else { return strainText(strain.strain) }
        let diff = strain.strain - target
        if diff >= 1 {
            return model.loc("Ziel erreicht – mehr bringt heute kaum Zusatznutzen, achte auf Erholung.",
                             "Target reached – more adds little benefit today, focus on recovery.")
        }
        if diff >= -1 {
            return model.loc("Du bist genau im Zielbereich für deine heutige Recovery.",
                             "You are right in the target zone for today\u{2019}s recovery.")
        }
        return String(format: model.loc("Der weiße Strich markiert dein Tagesziel (%.1f) – basierend auf deiner Recovery.",
                                        "The white tick marks your daily target (%.1f) – based on your recovery."), target)
    }

    private func zonesCard(_ strain: StrainResult) -> some View {
        let active = strain.zoneMinutes.reduce(0, +)
        return SectionCard(model.loc("Zeit in Intensitätszonen", "Time in intensity zones")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StatCell(label: model.loc("Aufgezeichnet", "Recorded"), value: durationText(strain.trackedMinutes))
                    StatCell(label: model.loc("Ruhe", "Rest"), value: durationText(strain.restMinutes))
                    StatCell(label: model.loc("Aktiv", "Active"), value: durationText(active))
                }
                if active >= 1 {
                    Divider().background(Theme.stroke)
                    ZoneBarsView(zoneMinutes: strain.zoneMinutes)
                } else if strain.trackedMinutes > 0 {
                    Text(model.loc("Heute keine Zeit oberhalb der Ruhezone – ein reiner Erholungstag. Die Zonen zählen nur aktive Belastung (ab ~20 % deiner Herzfrequenzreserve), nicht die ruhige Tragezeit.", "No time above the rest zone today – a pure recovery day. Zones only count active load (from ~20 % of your heart-rate reserve), not quiet wear time."))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    EmptyDataHint(text: model.loc("Noch keine Herzfrequenzdaten für diesen Tag.", "No heart-rate data for this day yet."))
                }
            }
        }
    }

    /// Minuten → "4 min" bzw. "3:50 h".
    private func durationText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return "\(Fmt.hm(minutes)) h"
    }

    private func strainText(_ value: Double) -> String {
        if model.language == .de {
            switch value {
            case ..<6: return "Leichter Tag – gut für Erholung."
            case ..<10: return "Moderate Belastung – Alltag mit etwas Aktivität."
            case ..<14: return "Solides Training – achte heute Abend auf Schlaf."
            case ..<18: return "Harte Belastung – dein Schlafbedarf steigt spürbar."
            default: return "Maximale Belastung – plane aktiv Erholung ein."
            }
        }
        switch value {
        case ..<6: return "Light day – good for recovery."
        case ..<10: return "Moderate load – everyday life with some activity."
        case ..<14: return "Solid training – prioritize sleep tonight."
        case ..<18: return "Hard effort – your sleep need rises noticeably."
        default: return "Maximum effort – actively plan recovery."
        }
    }

    @ViewBuilder
    private var hrCard: some View {
        if let record = model.selectedRecord, !record.hrSamples.isEmpty {
            SectionCard(model.loc("Herzfrequenz-Tagesverlauf", "Heart rate throughout the day")) {
                HRDayChart(samples: record.hrSamples)
            }
        }
    }

    @ViewBuilder
    private var workoutsCard: some View {
        if let record = model.selectedRecord, !record.workouts.isEmpty {
            SectionCard(model.loc("Workouts", "Workouts")) {
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
                                Text("\(Fmt.clock(workout.start))\(model.loc(" Uhr", "")) · \(Int(workout.durationMinutes.rounded())) min"
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
        SectionCard(model.loc("Strain – letzte 14 Tage", "Strain – last 14 days")) {
            let points = trendPoints(model.trend(14) { record in
                model.strain(for: record.date)?.strain
            })
            if points.count >= 2 {
                StrainLineChart(points: points)
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige Tage für den Trend.", "Not enough days for a trend yet."))
            }
        }
    }
}

import SwiftUI

struct AgeDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let result = model.ageResult(for: model.selectedDayKey) {
                    heroCard(result)
                    if result.pulseAge != nil {
                        breakdownCard(result)
                    }
                    vo2Card(result)
                    methodCard
                } else {
                    SectionCard {
                        EmptyDataHint(text: "Noch keine Daten für das Pulse Alter.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Pulse Alter")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private func heroCard(_ result: AgeResult) -> some View {
        SectionCard {
            if let pulseAge = result.pulseAge, let delta = result.deltaYears {
                VStack(spacing: 10) {
                    Text("\(Int(pulseAge.rounded()))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(DashboardView.deltaText(delta))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(DashboardView.deltaColor(delta))
                    Text("Dein biologisches Alter aus VO₂max, HRV, Ruhepuls, Schlaf und Aktivität – verglichen mit deinem chronologischen Alter von \(result.chronoAge) Jahren.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    if result.calibrating {
                        PillBadge(text: "kalibriert noch · Tag \(result.calibrationHave)/\(result.calibrationNeed)", color: Theme.yellow)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.teal)
                    Text("Wird kalibriert")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pulse braucht rund \(result.calibrationNeed) Tage mit nächtlichen Messwerten, um dein Alter stabil zu schätzen. Aktuell: Tag \(result.calibrationHave)/\(result.calibrationNeed).")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    ProgressView(value: Double(result.calibrationHave), total: Double(result.calibrationNeed))
                        .tint(Theme.teal)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Aufschlüsselung

    private func breakdownCard(_ result: AgeResult) -> some View {
        SectionCard("So setzt es sich zusammen") {
            VStack(spacing: 12) {
                ForEach(result.components) { component in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(component.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                if component.kind == .equivalent {
                                    Text("Äquivalenzalter")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.cardElevated))
                                }
                            }
                            Text(component.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(deltaBadge(component.deltaYears))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(DashboardView.deltaColor(component.deltaYears))
                    }
                }
                Divider().background(Theme.stroke)
                Text("VO₂max und HRV liefern je ein eigenes Äquivalenzalter (gewichtet 70 / 30). Ruhepuls, Schlaf und Aktivität sind gedeckelte Korrekturen (zusammen max. ±5 Jahre).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - VO₂max

    private func vo2Card(_ result: AgeResult) -> some View {
        SectionCard("Cardio-Fitness") {
            if let vo2 = result.vo2max {
                HStack(spacing: 16) {
                    StatCell(
                        label: "VO₂max",
                        value: String(format: "%.0f", vo2),
                        sub: "ml/kg/min",
                        color: Theme.teal
                    )
                    if let fitnessAge = result.fitnessAge {
                        StatCell(
                            label: "Fitness-Alter",
                            value: "\(Int(fitnessAge.rounded()))",
                            sub: "aus VO₂max",
                            color: Theme.textPrimary
                        )
                    }
                    StatCell(
                        label: "Quelle",
                        value: result.vo2maxEstimated ? "Geschätzt" : "Gemessen",
                        sub: result.vo2maxEstimated ? "HF-Ratio" : "Google Health",
                        color: result.vo2maxEstimated ? Theme.orange : Theme.green
                    )
                }
                if result.vo2maxEstimated {
                    Text("Kein gemessener VO₂max verfügbar – geschätzt über die Herzfrequenz-Ratio (15,3 × Maxpuls/Ruhepuls). Sobald die Fitbit Air per GPS-Lauf einen Cardio-Fitness-Wert liefert, nutzt Pulse diesen automatisch.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                EmptyDataHint(text: "Noch kein VO₂max – weder gemessen noch schätzbar (dafür braucht es Ruhepuls-Daten).")
            }
        }
    }

    // MARK: - Methodik

    private var methodCard: some View {
        SectionCard("Wie wird das gerechnet?") {
            VStack(alignment: .leading, spacing: 10) {
                methodRow("1.", "VO₂max → Fitness-Alter", "VO₂max ist der stärkste Einzelprädiktor der Lebenserwartung. Der Messwert wird über die FRIEND-Normwerte (50. Perzentil, geschlechtsspezifisch) in ein Alter übersetzt.")
                methodRow("2.", "HRV → HRV-Alter", "Der nächtliche RMSSD wird gegen alterstypische Referenzwerte verglichen.")
                methodRow("3.", "Korrekturen", "Ruhepuls (Mortalitäts-Gradient), Schlafperformance und Aktivität justieren das Ergebnis gedeckelt nach.")
                Divider().background(Theme.stroke)
                Text("Geschlecht (\(model.sex.label)) und Alter (\(model.age)) fließen in die Normkurven ein – anpassbar im Tab Mehr.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text("Quellen: FRIEND-Register (Kaminsky 2015) · Mandsager, JAMA Netw Open 2018 · Uth, Eur J Appl Physiol 2004 · Zhang, CMAJ 2016. Orientierung, kein medizinischer Befund.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
    }

    private func methodRow(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func deltaBadge(_ delta: Double) -> String {
        let rounded = Int(delta.rounded())
        if rounded == 0 { return "±0 J" }
        return rounded < 0 ? "\(rounded) J" : "+\(rounded) J"
    }
}

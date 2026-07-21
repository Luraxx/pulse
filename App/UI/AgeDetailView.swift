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
                        EmptyDataHint(text: model.loc("Noch keine Daten für das Pulse Alter.", "No data for Pulse Age yet."))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(model.loc("Pulse Alter", "Pulse Age"))
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
                    Text(model.loc("Dein biologisches Alter aus VO₂max, HRV, Ruhepuls, Schlaf und Aktivität – verglichen mit deinem chronologischen Alter von \(result.chronoAge) Jahren.", "Your biological age from VO₂max, HRV, resting HR, sleep and activity – compared to your chronological age of \(result.chronoAge) years."))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    if result.calibrating {
                        PillBadge(text: model.loc("kalibriert noch · Tag \(result.calibrationHave)/\(result.calibrationNeed)", "calibrating · day \(result.calibrationHave)/\(result.calibrationNeed)"), color: Theme.yellow)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.teal)
                    Text(model.loc("Wird kalibriert", "Calibrating"))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.loc("Pulse braucht rund \(result.calibrationNeed) Tage mit nächtlichen Messwerten, um dein Alter stabil zu schätzen. Aktuell: Tag \(result.calibrationHave)/\(result.calibrationNeed).", "Pulse needs about \(result.calibrationNeed) days of overnight data to estimate your age reliably. Currently: day \(result.calibrationHave)/\(result.calibrationNeed)."))
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
        SectionCard(model.loc("So setzt es sich zusammen", "How it is composed")) {
            VStack(spacing: 12) {
                ForEach(result.components) { component in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(component.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                if component.kind == .equivalent {
                                    Text(model.loc("Äquivalenzalter", "Equivalent age"))
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
                Text(model.loc("VO₂max und HRV liefern je ein eigenes Äquivalenzalter (gewichtet 70 / 30). Ruhepuls, Schlaf und Aktivität sind gedeckelte Korrekturen (zusammen max. ±5 Jahre).", "VO₂max and HRV each yield an equivalent age (weighted 70 / 30). Resting HR, sleep and activity are capped corrections (max. ±5 years combined)."))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - VO₂max

    private func vo2Card(_ result: AgeResult) -> some View {
        SectionCard(model.loc("Cardio-Fitness", "Cardio fitness")) {
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
                            label: model.loc("Fitness-Alter", "Fitness age"),
                            value: "\(Int(fitnessAge.rounded()))",
                            sub: model.loc("aus VO₂max", "from VO₂max"),
                            color: Theme.textPrimary
                        )
                    }
                    StatCell(
                        label: model.loc("Quelle", "Source"),
                        value: result.vo2maxEstimated ? model.loc("Geschätzt", "Estimated") : model.loc("Gemessen", "Measured"),
                        sub: result.vo2maxEstimated ? model.loc("HF-Ratio", "HR ratio") : "Google Health",
                        color: result.vo2maxEstimated ? Theme.orange : Theme.green
                    )
                }
                if result.vo2maxEstimated {
                    Text(model.loc("Kein gemessener VO₂max verfügbar – geschätzt über die Herzfrequenz-Ratio (15,3 × Maxpuls/Ruhepuls). Sobald die Fitbit Air per GPS-Lauf einen Cardio-Fitness-Wert liefert, nutzt Pulse diesen automatisch.", "No measured VO₂max available – estimated via the heart-rate ratio (15.3 × max HR / resting HR). Once the Fitbit Air provides a cardio fitness value from a GPS run, Pulse uses it automatically."))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                EmptyDataHint(text: model.loc("Noch kein VO₂max – weder gemessen noch schätzbar (dafür braucht es Ruhepuls-Daten).", "No VO₂max yet – neither measured nor estimable (requires resting HR data)."))
            }
        }
    }

    // MARK: - Methodik

    private var methodCard: some View {
        SectionCard(model.loc("Wie wird das gerechnet?", "How is this calculated?")) {
            VStack(alignment: .leading, spacing: 10) {
                methodRow("1.", model.loc("VO₂max → Fitness-Alter", "VO₂max → fitness age"), model.loc("VO₂max ist der stärkste Einzelprädiktor der Lebenserwartung. Der Messwert wird über die FRIEND-Normwerte (50. Perzentil, geschlechtsspezifisch) in ein Alter übersetzt.", "VO₂max is the strongest single predictor of life expectancy. The value is translated into an age via the FRIEND reference norms (50th percentile, sex-specific)."))
                methodRow("2.", model.loc("HRV → HRV-Alter", "HRV → HRV age"), model.loc("Der nächtliche RMSSD wird gegen alterstypische Referenzwerte verglichen.", "Nightly RMSSD is compared against age-typical reference values."))
                methodRow("3.", model.loc("Korrekturen", "Corrections"), model.loc("Ruhepuls (Mortalitäts-Gradient), Schlafperformance und Aktivität justieren das Ergebnis gedeckelt nach.", "Resting HR (mortality gradient), sleep performance and activity adjust the result within caps."))
                Divider().background(Theme.stroke)
                Text(model.loc("Geschlecht (\(model.sex.label(model.language))) und Alter (\(model.age)) fließen in die Normkurven ein – anpassbar im Tab Mehr.", "Sex (\(model.sex.label(model.language))) and age (\(model.age)) feed the reference curves – adjustable in the More tab."))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(model.loc("Quellen: FRIEND-Register (Kaminsky 2015) · Mandsager, JAMA Netw Open 2018 · Uth, Eur J Appl Physiol 2004 · Zhang, CMAJ 2016. Orientierung, kein medizinischer Befund.", "Sources: FRIEND registry (Kaminsky 2015) · Mandsager, JAMA Netw Open 2018 · Uth, Eur J Appl Physiol 2004 · Zhang, CMAJ 2016. Orientation, not a medical finding."))
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

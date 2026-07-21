import SwiftUI

struct RecoveryDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let recovery = model.recovery(for: model.selectedDayKey) {
                        heroCard(recovery)
                        componentsCard(recovery)
                        hrvCard(recovery)
                        rhrCard(recovery)
                    } else {
                        EmptyDataHint(text: model.loc("Keine Recovery-Daten für diesen Tag.", "No recovery data for this day."))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(_ recovery: RecoveryResult) -> some View {
        SectionCard {
            VStack(spacing: 12) {
                RingGauge(
                    progress: Double(recovery.score) / 100,
                    color: Theme.recoveryColor(zone: recovery.zone),
                    lineWidth: 18
                ) {
                    VStack(spacing: 2) {
                        Text("\(recovery.score)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("% Recovery")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity)

                Text(zoneText(recovery.zone))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if recovery.calibrating {
                    PillBadge(text: model.loc("Baseline kalibriert noch", "Baseline still calibrating"), color: Theme.yellow)
                }
            }
        }
    }

    private func zoneText(_ zone: RecoveryZone) -> String {
        if model.language == .de {
            switch zone {
            case .green: return "Dein Körper ist erholt – ein guter Tag für intensive Belastung."
            case .yellow: return "Mäßig erholt. Moderates Training ist okay, höre auf deinen Körper."
            case .red: return "Dein Körper braucht Erholung. Heute besser regenerieren."
            }
        }
        switch zone {
        case .green: return "Your body is recovered – a good day for intense effort."
        case .yellow: return "Moderately recovered. Moderate training is fine, listen to your body."
        case .red: return "Your body needs recovery. Better to regenerate today."
        }
    }

    private func componentsCard(_ recovery: RecoveryResult) -> some View {
        SectionCard(model.loc("Einflussfaktoren", "Contributing factors")) {
            VStack(spacing: 12) {
                ForEach(recovery.components, id: \.key) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(recoveryComponentLabel(component.key, fallback: component.label, model.language))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(model.loc("· Gewicht \(Int((component.weight * 100).rounded())) %", "· weight \(Int((component.weight * 100).rounded())) %"))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(component.detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardElevated)
                                Capsule()
                                    .fill(componentColor(component.score01))
                                    .frame(width: max(4, geo.size.width * CGFloat(component.score01)))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    private func componentColor(_ score: Double) -> Color {
        if score >= 0.62 { return Theme.green }
        if score >= 0.38 { return Theme.yellow }
        return Theme.red
    }

    private func hrvCard(_ recovery: RecoveryResult) -> some View {
        SectionCard(model.loc("HRV – letzte 30 Tage", "HRV – last 30 days")) {
            let points = trendPoints(model.trend(30) { $0.hrvRmssd })
            if points.count >= 2 {
                BaselineLineChart(
                    points: points,
                    baseline: recovery.hrvBaseline,
                    color: Theme.teal,
                    isLogBaseline: true
                )
                Text(model.loc("Band = persönliche Baseline ± 1 SD. Höher als das Band ist gut, darunter deutet auf Belastung hin.", "Band = personal baseline ± 1 SD. Above the band is good, below suggests strain."))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige HRV-Nächte.", "Not enough HRV nights yet."))
            }
        }
    }

    private func rhrCard(_ recovery: RecoveryResult) -> some View {
        SectionCard(model.loc("Ruhepuls – letzte 30 Tage", "Resting HR – last 30 days")) {
            let points = trendPoints(model.trend(30) { $0.restingHR })
            if points.count >= 2 {
                BaselineLineChart(
                    points: points,
                    baseline: recovery.rhrBaseline,
                    color: Theme.red
                )
                Text(model.loc("Ein erhöhter Ruhepuls gegenüber der Baseline ist ein frühes Zeichen für Stress, Krankheit oder unvollständige Erholung.", "A resting heart rate above your baseline is an early sign of stress, illness or incomplete recovery."))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: model.loc("Noch zu wenige Ruhepuls-Werte.", "Not enough resting HR values yet."))
            }
        }
    }
}

import SwiftUI

struct HealthMonitorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Nächtliche Messwerte im Vergleich zu deinem persönlichen 30-Tage-Baseline-Band (± 1,65 SD). Ausreißer sind frühe Warnzeichen für Krankheit oder Übertraining.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if model.hasData {
                            ForEach(model.healthStatuses, id: \.kind) { status in
                                metricCard(status)
                            }
                        } else {
                            EmptyDataHint(text: "Keine Daten vorhanden.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Gesundheit")
        }
    }

    private func metricCard(_ status: HealthMetricStatus) -> some View {
        SectionCard(status.kind.label) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if let value = status.value {
                        Text(status.kind.formatted(value))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(status.kind.unit)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("–")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    PillBadge(
                        text: Theme.bandLabel(status.state),
                        color: Theme.bandColor(status.state)
                    )
                }

                if let lower = status.lowerBound {
                    let upperText = status.upperBound.map { status.kind.formatted($0) } ?? "∞"
                    Text("Normalbereich: \(status.kind.formatted(lower)) – \(upperText) \(status.kind.unit)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if let baseline = status.baseline {
                    Text("Baseline: Ø \(status.kind.formatted(baseline.mean)) \(status.kind.unit) (\(baseline.count) Nächte)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                let points = trendPoints(model.trend(30) { record in
                    metricValue(status.kind, record)
                })
                if points.count >= 2 {
                    Sparkline(points: points, color: Theme.bandColor(status.state))
                }
            }
        }
    }

    private func metricValue(_ kind: HealthMetricKind, _ record: DayRecord) -> Double? {
        switch kind {
        case .restingHR: return record.restingHR
        case .hrv: return record.hrvRmssd
        case .respiratoryRate: return record.respiratoryRate
        case .spo2: return record.spo2Avg
        case .bodyTemp: return record.bodyTemp
        }
    }
}

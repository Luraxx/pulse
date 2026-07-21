import SwiftUI

struct HealthMonitorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Text(model.loc("Nächtliche Messwerte im Vergleich zu deinem persönlichen 30-Tage-Baseline-Band (± 1,65 SD). Ausreißer sind frühe Warnzeichen für Krankheit oder Übertraining.", "Overnight measurements compared to your personal 30-day baseline band (± 1.65 SD). Outliers are early warning signs of illness or overtraining."))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if model.hasData {
                            ForEach(model.healthStatuses, id: \.kind) { status in
                                metricCard(status)
                            }
                        } else {
                            EmptyDataHint(text: model.loc("Keine Daten vorhanden.", "No data available."))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(model.loc("Gesundheit", "Health"))
        }
    }

    private func metricCard(_ status: HealthMetricStatus) -> some View {
        SectionCard(status.kind.label(model.language)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if let value = status.value {
                        Text(status.kind.formatted(value))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(status.kind.unit(model.language))
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
                    Text(model.loc("Normalbereich: \(status.kind.formatted(lower)) – \(upperText) \(status.kind.unit(model.language))", "Normal range: \(status.kind.formatted(lower)) – \(upperText) \(status.kind.unit(model.language))"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if let baseline = status.baseline {
                    Text(model.loc("Baseline: Ø \(status.kind.formatted(baseline.mean)) \(status.kind.unit(model.language)) (\(baseline.count) Nächte)", "Baseline: avg \(status.kind.formatted(baseline.mean)) \(status.kind.unit(model.language)) (\(baseline.count) nights)"))
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

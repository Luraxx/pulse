import SwiftUI
import Charts

struct TrendPoint: Identifiable {
    let key: String
    let date: Date
    let value: Double

    var id: String { key }

    init?(key: String, value: Double) {
        guard let date = DayKey.date(from: key) else { return nil }
        self.key = key
        self.date = date
        self.value = value
    }
}

func trendPoints(_ pairs: [(key: String, value: Double)]) -> [TrendPoint] {
    pairs.compactMap { TrendPoint(key: $0.key, value: $0.value) }
}

// MARK: - Intraday-Herzfrequenz

struct HRDayChart: View {
    let samples: [HRSample]

    private var display: [HRSample] {
        guard samples.count > 240 else { return samples }
        let step = samples.count / 240 + 1
        return samples.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
    }

    var body: some View {
        let values = display.map(\.bpm)
        let lower = (values.min() ?? 40) - 8
        let upper = (values.max() ?? 180) + 12
        Chart(display, id: \.t) { sample in
            LineMark(
                x: .value("Zeit", sample.t),
                y: .value("Puls", sample.bpm)
            )
            .foregroundStyle(Theme.red.opacity(0.9))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.4))
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 150)
    }
}

// MARK: - Recovery-Balken

struct RecoveryBarsChart: View {
    let points: [TrendPoint]
    var height: CGFloat = 150

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Tag", point.date, unit: .day),
                y: .value("Recovery", point.value)
            )
            .foregroundStyle(Theme.recoveryColor(score: Int(point.value)))
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis { defaultXAxis() }
        .chartYAxis { defaultYAxis() }
        .frame(height: height)
    }
}

// MARK: - Strain-Linie

struct StrainLineChart: View {
    let points: [TrendPoint]
    var height: CGFloat = 150

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Tag", point.date, unit: .day),
                y: .value("Strain", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.strainBlue.opacity(0.35), Theme.strainBlue.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Tag", point.date, unit: .day),
                y: .value("Strain", point.value)
            )
            .foregroundStyle(Theme.strainBlue)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...21)
        .chartXAxis { defaultXAxis() }
        .chartYAxis { defaultYAxis() }
        .frame(height: height)
    }
}

// MARK: - Schlafdauer vs. Bedarf

struct SleepTrendChart: View {
    let slept: [TrendPoint] // Minuten
    let need: [TrendPoint]  // Minuten
    var height: CGFloat = 150

    var body: some View {
        Chart {
            ForEach(slept) { point in
                BarMark(
                    x: .value("Tag", point.date, unit: .day),
                    y: .value("Stunden", point.value / 60)
                )
                .foregroundStyle(Theme.sleepPurple.opacity(0.85))
                .cornerRadius(3)
            }
            ForEach(need) { point in
                LineMark(
                    x: .value("Tag", point.date, unit: .day),
                    y: .value("Bedarf", point.value / 60)
                )
                .foregroundStyle(.white.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .chartXAxis { defaultXAxis() }
        .chartYAxis { defaultYAxis() }
        .frame(height: height)
    }
}

// MARK: - Linie mit Baseline-Band

struct BaselineLineChart: View {
    let points: [TrendPoint]
    let baseline: Baseline?
    let color: Color
    var isLogBaseline = false
    var height: CGFloat = 150

    private var band: (lower: Double, upper: Double, mean: Double)? {
        guard let baseline else { return nil }
        if isLogBaseline {
            return (exp(baseline.mean - baseline.sd), exp(baseline.mean + baseline.sd), exp(baseline.mean))
        }
        return (baseline.mean - baseline.sd, baseline.mean + baseline.sd, baseline.mean)
    }

    var body: some View {
        Chart {
            if let band {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Tag", point.date, unit: .day),
                        yStart: .value("unten", band.lower),
                        yEnd: .value("oben", band.upper)
                    )
                    .foregroundStyle(color.opacity(0.10))
                }
                RuleMark(y: .value("Ø", band.mean))
                    .foregroundStyle(color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Tag", point.date, unit: .day),
                    y: .value("Wert", point.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .symbol(.circle)
                .symbolSize(16)
            }
        }
        .chartXAxis { defaultXAxis() }
        .chartYAxis { defaultYAxis() }
        .frame(height: height)
    }
}

// MARK: - Recovery + Strain kombiniert

struct RecoveryStrainChart: View {
    let recovery: [TrendPoint] // 0–100
    let strain: [TrendPoint]   // 0–21
    var height: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(recovery) { point in
                    BarMark(
                        x: .value("Tag", point.date, unit: .day),
                        y: .value("Recovery", point.value)
                    )
                    .foregroundStyle(Theme.recoveryColor(score: Int(point.value)).opacity(0.55))
                    .cornerRadius(3)
                }
                ForEach(strain) { point in
                    LineMark(
                        x: .value("Tag", point.date, unit: .day),
                        y: .value("Strain", point.value * 100 / 21)
                    )
                    .foregroundStyle(Theme.strainBlue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    .symbolSize(14)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis { defaultXAxis() }
            .chartYAxis { defaultYAxis() }
            .frame(height: height)

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.green.opacity(0.6)).frame(width: 10, height: 10)
                    Text("Recovery (%)")
                }
                HStack(spacing: 5) {
                    Capsule().fill(Theme.strainBlue).frame(width: 12, height: 3)
                    Text("Strain (skaliert auf 100)")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let points: [TrendPoint]
    let color: Color

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Tag", point.date, unit: .day),
                y: .value("Wert", point.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
    }
}

// MARK: - Gemeinsame Achsen

func defaultXAxis() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
        AxisGridLine().foregroundStyle(Theme.stroke)
        AxisValueLabel(format: .dateTime.day().month())
            .foregroundStyle(Theme.textSecondary)
    }
}

func defaultYAxis() -> some AxisContent {
    AxisMarks(position: .trailing) { _ in
        AxisGridLine().foregroundStyle(Theme.stroke)
        AxisValueLabel().foregroundStyle(Theme.textSecondary)
    }
}

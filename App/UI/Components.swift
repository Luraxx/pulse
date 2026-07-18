import SwiftUI

// MARK: - Karten

struct SectionCard<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
    }
}

// MARK: - Gauges

struct RingGauge<Center: View>: View {
    var progress: Double // 0–1
    var color: Color
    var lineWidth: CGFloat = 16
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.003, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
    }
}

/// 270°-Bogen für die Strain-Skala (0–21).
struct ArcGauge<Center: View>: View {
    var fraction: Double // 0–1
    var color: Color
    var lineWidth: CGFloat = 16
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(color.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * CGFloat(max(0.004, min(1, fraction))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            center
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Kleinteile

struct StatCell: View {
    let label: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PillBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

struct EmptyDataHint: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Intensitätszonen

struct ZoneBarsView: View {
    let zoneMinutes: [Double]

    var body: some View {
        let maxMinutes = max(zoneMinutes.max() ?? 1, 1)
        VStack(spacing: 8) {
            ForEach(Array(zoneMinutes.enumerated().reversed()), id: \.offset) { index, minutes in
                HStack(spacing: 10) {
                    Text(StrainEngine.zoneLabels[index])
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.cardElevated)
                            Capsule()
                                .fill(zoneColor(index))
                                .frame(width: max(3, geo.size.width * CGFloat(minutes / maxMinutes)))
                        }
                    }
                    .frame(height: 8)
                    Text(minutes >= 1 ? "\(Int(minutes.rounded())) min" : "–")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private func zoneColor(_ index: Int) -> Color {
        [Theme.textSecondary, Theme.teal, Theme.green, Theme.yellow, Theme.orange, Theme.red][min(index, 5)]
    }
}

// MARK: - Schlafphasen-Timeline (Hypnogramm)

struct StagesTimelineView: View {
    let session: SleepSession

    private let lanes: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(Fmt.clock(session.start))
                Spacer()
                Text(Fmt.clock(session.end))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)

            Canvas { context, size in
                let total = session.end.timeIntervalSince(session.start)
                guard total > 0 else { return }
                let laneHeight = size.height / CGFloat(lanes.count)

                // Lane-Hintergrundlinien
                for index in lanes.indices {
                    let y = CGFloat(index) * laneHeight + laneHeight / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Theme.stroke.opacity(0.6)), lineWidth: 1)
                }

                for span in session.stages {
                    guard let lane = lanes.firstIndex(of: span.stage == .unknown ? .light : span.stage) else { continue }
                    let x0 = CGFloat(span.start.timeIntervalSince(session.start) / total) * size.width
                    let x1 = CGFloat(span.end.timeIntervalSince(session.start) / total) * size.width
                    let rect = CGRect(
                        x: x0,
                        y: CGFloat(lane) * laneHeight + 3,
                        width: max(1.5, x1 - x0),
                        height: laneHeight - 6
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(Theme.stageColor(span.stage))
                    )
                }
            }
            .frame(height: 120)

            HStack(spacing: 14) {
                ForEach(lanes, id: \.self) { stage in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.stageColor(stage)).frame(width: 7, height: 7)
                        Text(Theme.stageName(stage))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Phasen-Verteilung

struct StageDistributionView: View {
    let stageMinutes: [SleepStage: Double]

    private var orderedStages: [(SleepStage, Double)] {
        [SleepStage.deep, .rem, .light, .awake].compactMap { stage in
            guard let minutes = stageMinutes[stage], minutes > 0 else { return nil }
            return (stage, minutes)
        }
    }

    var body: some View {
        let total = max(orderedStages.reduce(0) { $0 + $1.1 }, 1)
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(orderedStages, id: \.0) { stage, minutes in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.stageColor(stage))
                            .frame(width: max(2, geo.size.width * CGFloat(minutes / total)))
                    }
                }
            }
            .frame(height: 10)

            VStack(spacing: 6) {
                ForEach(orderedStages, id: \.0) { stage, minutes in
                    HStack {
                        Circle().fill(Theme.stageColor(stage)).frame(width: 8, height: 8)
                        Text(Theme.stageName(stage))
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Fmt.hm(minutes)) h")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Int((minutes / total * 100).rounded())) %")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}

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

/// 270°-Bogen für die Strain-Skala (0–21). `marker` (0–1) zeichnet einen
/// weißen Ziel-Strich auf den Bogen (wie Whoops Strain Target).
struct ArcGauge<Center: View>: View {
    var fraction: Double // 0–1
    var color: Color
    var lineWidth: CGFloat = 16
    var marker: Double? = nil
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
            if let marker {
                GeometryReader { geo in
                    let radius = min(geo.size.width, geo.size.height) / 2
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: lineWidth + 8)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2 - radius)
                        // 12-Uhr-Position → Startpunkt (135°) + Anteil des 270°-Bogens.
                        .rotationEffect(.degrees(Stats.clamp(marker, 0, 1) * 270 - 135))
                }
            }
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

// MARK: - Tages-Übersicht (3 Ringe)

/// Konzentrische Ringe: außen Recovery, Mitte Schlaf-Performance, innen
/// Strain relativ zum Tagesziel. Einheitliche Skala: „% von dem, was heute
/// für dich richtig ist".
struct TripleRingView: View {
    var recovery: Double?      // 0–1
    var sleep: Double?         // 0–1
    var strainOfTarget: Double? // 0–1 (Strain / Tagesziel, gekappt)
    var recoveryColor: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            ring(recovery, color: recoveryColor, inset: 0)
            ring(sleep, color: Theme.sleepPurple, inset: lineWidth + 3)
            ring(strainOfTarget, color: Theme.strainBlue, inset: 2 * (lineWidth + 3))
        }
        .padding(lineWidth / 2)
    }

    @ViewBuilder
    private func ring(_ value: Double?, color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(Stats.clamp(value ?? 0, 0.004, 1)))
                .stroke(
                    color.opacity(value == nil ? 0.25 : 1),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

/// Kompakte „Heute"-Übersicht ganz oben im Dashboard (tippbar → große Ringe).
struct TodayOverviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink {
            OverviewDetailView()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardContent: some View {
        let key = model.selectedDayKey
        let recovery = model.recovery(for: key)
        let sleep = model.sleep(for: key)
        let strain = model.strain(for: key)
        let target = recovery.map { StrainEngine.targetStrain(forRecovery: $0.score) }

        SectionCard {
            HStack(spacing: 18) {
                TripleRingView(
                    recovery: recovery.map { Double($0.score) / 100 },
                    sleep: (sleep?.hasData == true) ? (sleep.map { $0.performance / 100 }) : nil,
                    strainOfTarget: zip2(strain, target).map { min(1, $0.strain / max($1, 0.1)) },
                    recoveryColor: recovery.map { Theme.recoveryColor(zone: $0.zone) } ?? Theme.textSecondary
                )
                .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 9) {
                    overviewRow(
                        color: recovery.map { Theme.recoveryColor(zone: $0.zone) } ?? Theme.textSecondary,
                        label: "Recovery",
                        value: recovery.map { "\($0.score) %" } ?? "–"
                    )
                    overviewRow(
                        color: Theme.sleepPurple,
                        label: model.loc("Schlaf", "Sleep"),
                        value: (sleep?.hasData == true) ? "\(Int(sleep!.performance.rounded())) %" : "–"
                    )
                    overviewRow(
                        color: Theme.strainBlue,
                        label: "Strain",
                        value: strain.map { s in
                            target.map { String(format: "%.1f / Ziel %.1f", s.strain, $0) }
                                ?? String(format: "%.1f", s.strain)
                        } ?? "–"
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func overviewRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Kleines Helferlein: zip für zwei Optionals.
/// Recovery-Komponenten kommen mit deutschem Label aus der Engine — der
/// stabile key erlaubt die Übersetzung im UI.
func recoveryComponentLabel(_ key: String, fallback: String, _ lang: PulseLanguage) -> String {
    guard lang == .en else { return fallback }
    switch key {
    case "hrv": return "HRV"
    case "rhr": return "Resting HR"
    case "sleep": return "Sleep"
    case "resp": return "Respiration"
    default: return fallback
    }
}

func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: - Journal

/// Faktor-Chips für einen Tag — genutzt von der Dashboard-Karte und dem
/// Morgen-Popup.
struct JournalFactorGrid: View {
    @Environment(AppModel.self) private var model
    let dayKey: String

    var body: some View {
        let entry = model.journalEntry(for: dayKey)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(JournalFactor.allCases) { factor in
                let active = entry.factors.contains(factor)
                Button {
                    model.toggleJournal(factor, on: dayKey)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: factor.symbol)
                            .font(.caption)
                        Text(factor.label(model.language))
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active ? Theme.teal.opacity(0.20) : Theme.cardElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(active ? Theme.teal : .clear, lineWidth: 1)
                    )
                    .foregroundStyle(active ? Theme.teal : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct JournalCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard("Journal") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.loc("Was war los? Wirkt sich auf die Recovery der nächsten Nacht aus.", "What happened? Affects the next night\u{2019}s recovery."))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                JournalFactorGrid(dayKey: model.selectedDayKey)
            }
        }
    }
}

/// Morgen-Popup: kurzer Check-in für gestern, sobald neue Daten da sind.
struct JournalPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dayKey: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Fmt.dayTitle(dayKey))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.loc("Kurzer Check-in: Was war los? Je vollständiger dein Journal, desto besser werden deine Korrelationen.", "Quick check-in: what happened? The more complete your journal, the better your correlations."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    JournalFactorGrid(dayKey: dayKey)
                    Button {
                        dismiss()
                    } label: {
                        Text(model.loc("Fertig", "Done"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.teal))
                            .foregroundStyle(Color.black)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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
                    Text(StrainEngine.zoneLabels(Fmt.language)[index])
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

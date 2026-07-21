import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var showCustomize = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if model.hasData {
                    content
                } else {
                    EmptyDataHint(text: model.isConnected
                        ? model.loc("Noch keine Daten – starte oben rechts eine Synchronisierung.", "No data yet – tap sync in the top right corner.")
                        : model.loc("Keine Daten vorhanden. Verbinde Google Health oder starte den Demo-Modus unter „Mehr“.", "No data. Connect Google Health or start demo mode under More."))
                }
            }
            .navigationTitle(Fmt.dayTitle(model.selectedDayKey))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if model.demoMode {
                    ToolbarItem(placement: .topBarLeading) {
                        PillBadge(text: "Demo", color: Theme.yellow)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCustomize = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isConnected {
                        Button {
                            Task { await model.syncNow() }
                        } label: {
                            if model.syncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(model.syncing)
                    }
                }
            }
            .sheet(isPresented: $showCustomize) {
                DashboardCustomizeSheet()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                DayChips()

                if model.syncing {
                    syncBanner
                }
                if let error = model.lastError, !model.syncing {
                    errorBanner(error)
                }
                if let alert = model.healthAlert {
                    alertBanner(alert)
                }

                ForEach(model.visibleModules) { module in
                    moduleView(module)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            if model.isConnected {
                await model.syncNow()
            }
        }
    }

    // MARK: - Module

    @ViewBuilder
    private func moduleView(_ module: DashboardModule) -> some View {
        switch module {
        case .overview: TodayOverviewCard()
        case .recovery: recoveryCard
        case .age: ageCard
        case .sleep: sleepCard
        case .strain: strainCard
        case .workouts: WorkoutsCard()
        case .steps: StepsCard()
        case .health: healthCard
        case .journal: JournalCard()
        }
    }

    // MARK: - Banner

    private var syncBanner: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                    Text(model.syncMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: model.syncFraction)
                    .tint(Theme.teal)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.yellow)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    model.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func alertBanner(_ alert: HealthAlert) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.loc("Gesundheits-Hinweis", "Health notice"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Recovery

    private var recoveryCard: some View {
        NavigationLink {
            RecoveryDetailView()
        } label: {
            SectionCard("Recovery") {
                if let recovery = model.recovery(for: model.selectedDayKey) {
                    HStack(spacing: 18) {
                        RingGauge(
                            progress: Double(recovery.score) / 100,
                            color: Theme.recoveryColor(zone: recovery.zone),
                            lineWidth: 14
                        ) {
                            VStack(spacing: 0) {
                                Text("\(recovery.score)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("%")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 132, height: 132)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recovery.components, id: \.key) { component in
                                HStack {
                                    Text(recoveryComponentLabel(component.key, fallback: component.label, model.language))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(component.detail)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            if recovery.calibrating {
                                Text(model.loc("Baseline kalibriert noch (< 5 Nächte)", "Baseline still calibrating (< 5 nights)"))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.yellow)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: model.loc("Keine Recovery-Daten für diesen Tag.", "No recovery data for this day."))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pulse Alter

    private var ageCard: some View {
        NavigationLink {
            AgeDetailView()
        } label: {
            SectionCard(model.loc("Pulse Alter", "Pulse Age")) {
                if let result = model.ageResult(for: model.selectedDayKey) {
                    if let pulseAge = result.pulseAge, let delta = result.deltaYears {
                        HStack(spacing: 18) {
                            VStack(spacing: 0) {
                                Text("\(Int(pulseAge.rounded()))")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(model.loc("Jahre", "years"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(width: 108)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(Self.deltaText(delta))
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Self.deltaColor(delta))
                                Text(model.loc("Chronologisch: \(result.chronoAge) Jahre", "Chronological: \(result.chronoAge) years"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                if let vo2 = result.vo2max {
                                    Text(String(format: "VO₂max %.0f%@", vo2, result.vo2maxEstimated ? model.loc(" (geschätzt)", " (estimated)") : ""))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                if result.calibrating {
                                    Text(model.loc("kalibriert noch · Tag \(result.calibrationHave)/\(result.calibrationNeed)", "calibrating · day \(result.calibrationHave)/\(result.calibrationNeed)"))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.yellow)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.loc("Wird kalibriert …", "Calibrating …"))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(model.loc("Sammle mind. \(result.calibrationNeed) Tage Daten – aktuell Tag \(result.calibrationHave)/\(result.calibrationNeed).", "Collecting at least \(result.calibrationNeed) days of data – currently day \(result.calibrationHave)/\(result.calibrationNeed)."))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            ProgressView(value: Double(result.calibrationHave), total: Double(result.calibrationNeed))
                                .tint(Theme.teal)
                        }
                    }
                } else {
                    EmptyDataHint(text: model.loc("Noch keine Daten für das Pulse Alter.", "No data for Pulse Age yet."))
                }
            }
        }
        .buttonStyle(.plain)
    }

    static func deltaText(_ delta: Double) -> String {
        let rounded = Int(abs(delta).rounded())
        if Fmt.language == .de {
            if rounded == 0 { return "Genau in deinem Alter" }
            let unit = rounded == 1 ? "Jahr" : "Jahre"
            return delta < 0 ? "\(rounded) \(unit) jünger" : "\(rounded) \(unit) älter"
        }
        if rounded == 0 { return "Exactly your age" }
        let unit = rounded == 1 ? "year" : "years"
        return delta < 0 ? "\(rounded) \(unit) younger" : "\(rounded) \(unit) older"
    }

    static func deltaColor(_ delta: Double) -> Color {
        if delta <= -1 { return Theme.green }
        if delta >= 1 { return Theme.orange }
        return Theme.textSecondary
    }

    // MARK: - Schlaf

    private var sleepCard: some View {
        NavigationLink {
            SleepDetailView()
        } label: {
            SectionCard(model.loc("Schlaf", "Sleep")) {
                if let sleep = model.sleep(for: model.selectedDayKey), sleep.hasData {
                    HStack(spacing: 18) {
                        RingGauge(
                            progress: sleep.performance / 100,
                            color: Theme.sleepPurple,
                            lineWidth: 10
                        ) {
                            VStack(spacing: 0) {
                                Text("\(Int(sleep.performance.rounded()))")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("%")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 92, height: 92)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.loc("\(Fmt.hm(sleep.sleptMinutes)) von \(Fmt.hm(sleep.needMinutes)) h", "\(Fmt.hm(sleep.sleptMinutes)) of \(Fmt.hm(sleep.needMinutes)) h"))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            if let bed = sleep.bedTime, let wake = sleep.wakeTime {
                                Text(model.loc("\(Fmt.clock(bed)) – \(Fmt.clock(wake)) Uhr", "\(Fmt.clock(bed)) – \(Fmt.clock(wake))"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if sleep.debtAfterMinutes > 5 {
                                Text(model.loc("Schlafschuld: \(Fmt.hm(sleep.debtAfterMinutes)) h", "Sleep debt: \(Fmt.hm(sleep.debtAfterMinutes)) h"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.orange)
                            } else {
                                Text(model.loc("Keine Schlafschuld", "No sleep debt"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.green)
                            }
                            if model.selectedDayKey == DayKey.today(),
                               let bed = model.bedtimeTonight?.recommendedBedtimeMinutes {
                                Label(model.loc("Ziel heute: bis \(Fmt.clockFromMinutes(bed)) ins Bett", "Tonight: in bed by \(Fmt.clockFromMinutes(bed))"), systemImage: "bed.double")
                                    .font(.caption)
                                    .foregroundStyle(Theme.teal)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: model.loc("Kein Schlaf für diesen Tag erfasst.", "No sleep recorded for this day."))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Strain

    private var strainCard: some View {
        NavigationLink {
            StrainDetailView()
        } label: {
            SectionCard(model.loc("Tagesbelastung", "Daily strain")) {
                if let strain = model.strain(for: model.selectedDayKey) {
                    let target = model.recovery(for: model.selectedDayKey)
                        .map { StrainEngine.targetStrain(forRecovery: $0.score) }
                    HStack(spacing: 18) {
                        ArcGauge(
                            fraction: strain.strain / 21,
                            color: Theme.strainBlue,
                            lineWidth: 12,
                            marker: target.map { $0 / 21 }
                        ) {
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f", strain.strain))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(model.loc("von 21", "of 21"))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 108, height: 108)

                        VStack(alignment: .leading, spacing: 6) {
                            if let target {
                                Text(model.loc("Ziel heute: \(String(format: "%.1f", target))", "Today\u{2019}s target: \(String(format: "%.1f", target))"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.strainBlue)
                            }
                            let active = strain.zoneMinutes.dropFirst(2).reduce(0, +)
                            Text(model.loc("\(Int(active.rounded())) min fordernd oder härter", "\(Int(active.rounded())) min demanding or harder"))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            if let record = model.selectedRecord, !record.workouts.isEmpty {
                                ForEach(record.workouts.prefix(2), id: \.id) { workout in
                                    HStack(spacing: 6) {
                                        Image(systemName: "figure.run")
                                            .font(.caption)
                                            .foregroundStyle(Theme.strainBlue)
                                        Text(workout.name)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        if let workoutStrain = workout.strain {
                                            Text(String(format: "%.1f", workoutStrain))
                                                .font(.caption.monospacedDigit().weight(.semibold))
                                                .foregroundStyle(Theme.strainBlue)
                                        }
                                    }
                                }
                            } else {
                                Text(model.loc("Kein Workout erfasst", "No workout recorded"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let peak = strain.peakHR {
                                Text(model.loc("Max. Puls: \(Int(peak.rounded()))", "Max HR: \(Int(peak.rounded()))"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: model.loc("Keine Belastungsdaten für diesen Tag.", "No strain data for this day."))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health-Monitor

    private var healthCard: some View {
        SectionCard(model.loc("Health-Monitor", "Health monitor")) {
            let statuses = model.healthStatuses
            if statuses.allSatisfy({ $0.state == .noData }) {
                EmptyDataHint(text: model.loc("Keine nächtlichen Messwerte für diesen Tag.", "No overnight measurements for this day."))
            } else {
                VStack(spacing: 10) {
                    ForEach(statuses, id: \.kind) { status in
                        HStack {
                            Circle()
                                .fill(Theme.bandColor(status.state))
                                .frame(width: 8, height: 8)
                            Text(status.kind.label(model.language))
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let value = status.value {
                                Text("\(status.kind.formatted(value)) \(status.kind.unit(model.language))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            Text(Theme.bandLabel(status.state))
                                .font(.caption2)
                                .foregroundStyle(Theme.bandColor(status.state))
                                .frame(width: 74, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let lastSync = model.lastSyncAt {
                Text(model.loc("Letzter Sync: \(Fmt.relative(lastSync))", "Last sync: \(Fmt.relative(lastSync))"))
            } else if model.demoMode {
                Text(model.loc("Demo-Modus – generierte Beispieldaten", "Demo mode – generated sample data"))
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 4)
    }
}

// MARK: - Tages-Chips

struct DayChips: View {
    @Environment(AppModel.self) private var model

    private var keys: [String] {
        let today = DayKey.today()
        return DayKey.keys(from: DayKey.addDays(today, -20), to: today)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        chip(key).id(key)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(model.selectedDayKey, anchor: .trailing)
            }
        }
    }

    private func chip(_ key: String) -> some View {
        let isSelected = key == model.selectedDayKey
        let score = model.recovery(for: key)?.score
        return Button {
            model.selectedDayKey = key
        } label: {
            VStack(spacing: 5) {
                Text(Fmt.weekdayLetter(key))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(Fmt.dayNumber(key))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Circle()
                    .fill(score.map { Theme.recoveryColor(score: $0) } ?? Theme.stroke)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 42, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.cardElevated : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.teal : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if model.hasData {
                    content
                } else {
                    EmptyDataHint(text: model.isConnected
                        ? "Noch keine Daten – starte oben rechts eine Synchronisierung."
                        : "Keine Daten vorhanden. Verbinde Google Health oder starte den Demo-Modus unter „Mehr“.")
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

                recoveryCard
                sleepCard
                strainCard
                healthCard
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
                                    Text(component.label)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text(component.detail)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            if recovery.calibrating {
                                Text("Baseline kalibriert noch (< 5 Nächte)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.yellow)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: "Keine Recovery-Daten für diesen Tag.")
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schlaf

    private var sleepCard: some View {
        NavigationLink {
            SleepDetailView()
        } label: {
            SectionCard("Schlaf") {
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
                            Text("\(Fmt.hm(sleep.sleptMinutes)) von \(Fmt.hm(sleep.needMinutes)) h")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            if let bed = sleep.bedTime, let wake = sleep.wakeTime {
                                Text("\(Fmt.clock(bed)) – \(Fmt.clock(wake)) Uhr")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if sleep.debtAfterMinutes > 5 {
                                Text("Schlafschuld: \(Fmt.hm(sleep.debtAfterMinutes)) h")
                                    .font(.caption)
                                    .foregroundStyle(Theme.orange)
                            } else {
                                Text("Keine Schlafschuld")
                                    .font(.caption)
                                    .foregroundStyle(Theme.green)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: "Kein Schlaf für diesen Tag erfasst.")
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
            SectionCard("Tagesbelastung") {
                if let strain = model.strain(for: model.selectedDayKey) {
                    HStack(spacing: 18) {
                        ArcGauge(
                            fraction: strain.strain / 21,
                            color: Theme.strainBlue,
                            lineWidth: 12
                        ) {
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f", strain.strain))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("von 21")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 108, height: 108)

                        VStack(alignment: .leading, spacing: 6) {
                            let active = strain.zoneMinutes.dropFirst(2).reduce(0, +)
                            Text("\(Int(active.rounded())) min fordernd oder härter")
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
                                Text("Kein Workout erfasst")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let peak = strain.peakHR {
                                Text("Max. Puls: \(Int(peak.rounded()))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: "Keine Belastungsdaten für diesen Tag.")
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health-Monitor

    private var healthCard: some View {
        SectionCard("Health-Monitor") {
            let statuses = model.healthStatuses
            if statuses.allSatisfy({ $0.state == .noData }) {
                EmptyDataHint(text: "Keine nächtlichen Messwerte für diesen Tag.")
            } else {
                VStack(spacing: 10) {
                    ForEach(statuses, id: \.kind) { status in
                        HStack {
                            Circle()
                                .fill(Theme.bandColor(status.state))
                                .frame(width: 8, height: 8)
                            Text(status.kind.label)
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if let value = status.value {
                                Text("\(status.kind.formatted(value)) \(status.kind.unit)")
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
                Text("Letzter Sync: \(Fmt.relative(lastSync))")
            } else if model.demoMode {
                Text("Demo-Modus – generierte Beispieldaten")
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

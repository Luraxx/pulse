import SwiftUI

/// Übersichts-Seite: die drei Ringe groß nebeneinander, gestaffelt animiert.
/// Jeder Ring führt zur jeweiligen Detail-Seite.
struct OverviewDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var appear = false

    var body: some View {
        let key = model.selectedDayKey
        let recovery = model.recovery(for: key)
        let sleep = model.sleep(for: key)
        let strain = model.strain(for: key)
        let target = recovery.map { StrainEngine.targetStrain(forRecovery: $0.score) }

        ScrollView {
            VStack(spacing: 22) {
                Text(Fmt.dayTitle(key))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 12) {
                    ringColumn(
                        index: 0,
                        value: recovery.map { Double($0.score) / 100 },
                        color: recovery.map { Theme.recoveryColor(zone: $0.zone) } ?? Theme.textSecondary,
                        title: "Recovery",
                        valueText: recovery.map { "\($0.score) %" } ?? "–",
                        subText: recovery.map { $0.calibrating ? "kalibriert noch" : zoneName($0.zone) }
                    ) {
                        RecoveryDetailView()
                    }
                    ringColumn(
                        index: 1,
                        value: (sleep?.hasData == true) ? sleep.map { $0.performance / 100 } : nil,
                        color: Theme.sleepPurple,
                        title: "Schlaf",
                        valueText: (sleep?.hasData == true) ? "\(Int(sleep!.performance.rounded())) %" : "–",
                        subText: (sleep?.hasData == true) ? "\(Fmt.hm(sleep!.sleptMinutes)) h geschlafen" : nil
                    ) {
                        SleepDetailView()
                    }
                    ringColumn(
                        index: 2,
                        value: zip2(strain, target).map { min(1, $0.strain / max($1, 0.1)) },
                        color: Theme.strainBlue,
                        title: "Strain",
                        valueText: strain.map { String(format: "%.1f", $0.strain) } ?? "–",
                        subText: target.map { String(format: "Ziel %.1f", $0) }
                    ) {
                        StrainDetailView()
                    }
                }

                Text("Jeder Ring zeigt, wie viel von deinem heutigen Soll erreicht ist – antippen für Details.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Übersicht")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            appear = true
        }
        .onDisappear {
            appear = false
        }
    }

    @ViewBuilder
    private func ringColumn<Destination: View>(
        index: Int,
        value: Double?,
        color: Color,
        title: String,
        valueText: String,
        subText: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 10) {
                RingGauge(
                    progress: appear ? (value ?? 0.003) : 0.003,
                    color: color.opacity(value == nil ? 0.35 : 1),
                    lineWidth: 11
                ) {
                    Text(valueText)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(height: 104)
                .animation(
                    .spring(response: 0.85, dampingFraction: 0.75).delay(Double(index) * 0.15),
                    value: appear
                )

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subText ?? " ")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    private func zoneName(_ zone: RecoveryZone) -> String {
        switch zone {
        case .green: return "gut erholt"
        case .yellow: return "mäßig erholt"
        case .red: return "wenig erholt"
        }
    }
}

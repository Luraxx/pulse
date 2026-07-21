import SwiftUI

// MARK: - Dashboard-Module

/// Die anpassbaren Karten der Heute-Seite. Reihenfolge und Sichtbarkeit
/// werden in den Einstellungen persistiert.
enum DashboardModule: String, CaseIterable, Codable, Identifiable {
    case overview
    case recovery
    case age
    case sleep
    case strain
    case workouts
    case steps
    case health
    case journal

    var id: String { rawValue }

    func title(_ lang: PulseLanguage) -> String {
        switch (self, lang) {
        case (.overview, .de): return "Tages-Übersicht"
        case (.overview, .en): return "Daily overview"
        case (.recovery, _): return "Recovery"
        case (.age, .de): return "Pulse Alter"
        case (.age, .en): return "Pulse Age"
        case (.sleep, .de): return "Schlaf"
        case (.sleep, .en): return "Sleep"
        case (.strain, .de): return "Tagesbelastung"
        case (.strain, .en): return "Daily strain"
        case (.workouts, .de): return "Sport"
        case (.workouts, .en): return "Workouts"
        case (.steps, .de): return "Schritte"
        case (.steps, .en): return "Steps"
        case (.health, .de): return "Health-Monitor"
        case (.health, .en): return "Health monitor"
        case (.journal, _): return "Journal"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "circle.circle"
        case .recovery: return "arrow.clockwise.heart"
        case .age: return "person.text.rectangle"
        case .sleep: return "bed.double"
        case .strain: return "flame"
        case .workouts: return "figure.run"
        case .steps: return "shoeprints.fill"
        case .health: return "heart.text.square"
        case .journal: return "checklist"
        }
    }
}

// MARK: - Anpassen-Sheet

/// Reihenfolge per Drag ändern, Sichtbarkeit per Toggle.
struct DashboardCustomizeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.moduleOrder) { module in
                        HStack(spacing: 12) {
                            Image(systemName: module.symbol)
                                .foregroundStyle(Theme.teal)
                                .frame(width: 26)
                            Text(module.title(model.language))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !model.hiddenModules.contains(module) },
                                set: { model.setModule(module, visible: $0) }
                            ))
                            .labelsHidden()
                            .tint(Theme.teal)
                        }
                    }
                    .onMove { from, to in
                        model.moveModules(from: from, to: to)
                    }
                } footer: {
                    Text(model.loc("Ziehen zum Sortieren, Schalter zum Ein-/Ausblenden. Gilt für die Heute-Seite.", "Drag to reorder, toggle to show/hide. Applies to the Today page."))
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(model.loc("Heute anpassen", "Customize Today"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.loc("Fertig", "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sport-Karte (heutige Workouts)

struct WorkoutsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink {
            StrainDetailView()
        } label: {
            SectionCard(model.loc("Sport", "Workouts")) {
                if let record = model.selectedRecord, !record.workouts.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(record.workouts, id: \.id) { workout in
                            HStack(spacing: 12) {
                                Image(systemName: "figure.run")
                                    .font(.title3)
                                    .foregroundStyle(Theme.strainBlue)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(Fmt.clock(workout.start))\(model.loc(" Uhr", "")) · \(Int(workout.durationMinutes.rounded())) min"
                                         + (workout.averageHR.map { " · Ø \(Int($0.rounded()))" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if let strain = workout.strain {
                                    VStack(spacing: 0) {
                                        Text(String(format: "%.1f", strain))
                                            .font(.system(.title3, design: .rounded).weight(.bold))
                                            .foregroundStyle(Theme.strainBlue)
                                        Text("Strain")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    EmptyDataHint(text: model.loc("Kein Workout an diesem Tag erfasst.", "No workout recorded on this day."))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schritte-Karte

struct StepsCard: View {
    @Environment(AppModel.self) private var model

    private static let goal = 8000.0

    var body: some View {
        SectionCard(model.loc("Schritte", "Steps")) {
            if let steps = model.selectedRecord?.steps {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(steps)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(model.loc("von \(Int(Self.goal)) Schritten", "of \(Int(Self.goal)) steps"))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if Double(steps) >= Self.goal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.cardElevated)
                            Capsule()
                                .fill(Double(steps) >= Self.goal ? Theme.green : Theme.teal)
                                .frame(width: max(4, geo.size.width * CGFloat(min(1, Double(steps) / Self.goal))))
                        }
                    }
                    .frame(height: 8)
                }
            } else {
                EmptyDataHint(text: model.loc("Keine Schritte für diesen Tag erfasst.", "No steps recorded for this day."))
            }
        }
    }
}

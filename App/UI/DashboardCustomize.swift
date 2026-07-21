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

    var title: String {
        switch self {
        case .overview: return "Tages-Übersicht"
        case .recovery: return "Recovery"
        case .age: return "Pulse Alter"
        case .sleep: return "Schlaf"
        case .strain: return "Tagesbelastung"
        case .workouts: return "Sport"
        case .steps: return "Schritte"
        case .health: return "Health-Monitor"
        case .journal: return "Journal"
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
                            Text(module.title)
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
                    Text("Ziehen zum Sortieren, Schalter zum Ein-/Ausblenden. Gilt für die Heute-Seite.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Heute anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
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
            SectionCard("Sport") {
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
                                    Text("\(Fmt.clock(workout.start)) Uhr · \(Int(workout.durationMinutes.rounded())) min"
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
                    EmptyDataHint(text: "Kein Workout an diesem Tag erfasst.")
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
        SectionCard("Schritte") {
            if let steps = model.selectedRecord?.steps {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(steps)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("von \(Int(Self.goal)) Schritten")
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
                EmptyDataHint(text: "Keine Schritte für diesen Tag erfasst.")
            }
        }
    }
}

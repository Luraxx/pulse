import WidgetKit
import SwiftUI

// Eigenständiges Widget-Target. Liest den Recovery-Snapshot aus dem geteilten
// App-Group-Container (die App schreibt ihn via WidgetBridge). Bewusst ohne
// Core-Abhängigkeit — nur Primitive.

private let appGroup = "group.net.dehlwes.pulse"

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let score: Int?
    let zone: String
}

struct RecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry {
        RecoveryEntry(date: Date(), score: 72, zone: "green")
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
        // Recovery ändert sich real nur 1× pro Nacht — ein Refresh alle 2 h reicht.
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
        completion(Timeline(entries: [readEntry()], policy: .after(next)))
    }

    private func readEntry() -> RecoveryEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let score = defaults?.object(forKey: "recovery.score") as? Int
        let zone = defaults?.string(forKey: "recovery.zone") ?? "none"
        return RecoveryEntry(date: Date(), score: score, zone: zone)
    }
}

struct PulseWidgetEntryView: View {
    var entry: RecoveryEntry

    private var color: Color {
        switch entry.zone {
        case "green": return Color(red: 0.184, green: 0.839, blue: 0.451)
        case "yellow": return Color(red: 0.961, green: 0.773, blue: 0.259)
        case "red": return Color(red: 0.937, green: 0.325, blue: 0.314)
        default: return Color(red: 0.54, green: 0.59, blue: 0.65)
        }
    }

    var body: some View {
        ZStack {
            if let score = entry.score {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.01, min(1, Double(score) / 100))))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Recovery")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(color)
                    Text("Öffne Pulse")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(14)
        .containerBackground(Color.black, for: .widget)
    }
}

@main
struct PulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseRecovery", provider: RecoveryProvider()) { entry in
            PulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("Dein aktueller Recovery-Score auf einen Blick.")
        .supportedFamilies([.systemSmall])
    }
}

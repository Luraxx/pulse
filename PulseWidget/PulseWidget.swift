import WidgetKit
import SwiftUI

// Eigenständiges Widget-Target. Liest den Tages-Snapshot aus dem geteilten
// App-Group-Container (die App schreibt ihn via WidgetBridge). Bewusst ohne
// Core-Abhängigkeit — nur Primitive.

private let appGroup = "group.net.dehlwes.pulse"

/// Sprache aus dem App-Snapshot ("de"/"en", Default de).
private var widgetIsGerman: Bool {
    (UserDefaults(suiteName: appGroup)?.string(forKey: "app.language") ?? "de") == "de"
}

// MARK: - Daten

struct PulseEntry: TimelineEntry {
    let date: Date
    let score: Int?
    let zone: String
    let sleepPerformance: Double?
    let strain: Double?
    let strainTarget: Double?
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), score: 72, zone: "green", sleepPerformance: 88, strain: 9.5, strainTarget: 14.4)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        // Werte ändern sich real nur nach einem Sync — 2-h-Refresh reicht.
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
        completion(Timeline(entries: [readEntry()], policy: .after(next)))
    }

    private func readEntry() -> PulseEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return PulseEntry(
            date: Date(),
            score: defaults?.object(forKey: "recovery.score") as? Int,
            zone: defaults?.string(forKey: "recovery.zone") ?? "none",
            sleepPerformance: defaults?.object(forKey: "sleep.performance") as? Double,
            strain: defaults?.object(forKey: "strain.value") as? Double,
            strainTarget: defaults?.object(forKey: "strain.target") as? Double
        )
    }
}

// MARK: - Farben & Bausteine

private func zoneColor(_ zone: String) -> Color {
    switch zone {
    case "green": return Color(red: 0.184, green: 0.839, blue: 0.451)
    case "yellow": return Color(red: 0.961, green: 0.773, blue: 0.259)
    case "red": return Color(red: 0.937, green: 0.325, blue: 0.314)
    default: return Color(red: 0.54, green: 0.59, blue: 0.65)
    }
}

private let sleepPurple = Color(red: 0.608, green: 0.549, blue: 1.0)
private let strainBlue = Color(red: 0.290, green: 0.616, blue: 1.0)

private struct WidgetRing: View {
    var value: Double? // 0–1
    var color: Color
    var lineWidth: CGFloat
    var inset: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value ?? 0, 0.01), 1)))
                .stroke(
                    color.opacity(value == nil ? 0.25 : 1),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

// MARK: - Kleines Widget: Recovery-Ring

struct RecoveryWidgetView: View {
    var entry: PulseEntry

    var body: some View {
        ZStack {
            if let score = entry.score {
                Circle()
                    .stroke(zoneColor(entry.zone).opacity(0.16), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.01, min(1, Double(score) / 100))))
                    .stroke(zoneColor(entry.zone), style: StrokeStyle(lineWidth: 10, lineCap: .round))
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
                        .foregroundStyle(zoneColor("none"))
                    Text(widgetIsGerman ? "Öffne Pulse" : "Open Pulse")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(14)
        .containerBackground(Color.black, for: .widget)
    }
}

struct PulseRecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseRecovery", provider: PulseProvider()) { entry in
            RecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description(widgetIsGerman ? "Dein aktueller Recovery-Score auf einen Blick." : "Your current recovery score at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Mittleres Widget: Tages-Übersicht (3 Ringe)

struct OverviewWidgetView: View {
    var entry: PulseEntry

    private var strainOfTarget: Double? {
        guard let strain = entry.strain, let target = entry.strainTarget, target > 0 else { return nil }
        return min(1, strain / target)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                WidgetRing(value: entry.score.map { Double($0) / 100 }, color: zoneColor(entry.zone), lineWidth: 9, inset: 0)
                WidgetRing(value: entry.sleepPerformance.map { $0 / 100 }, color: sleepPurple, lineWidth: 9, inset: 12)
                WidgetRing(value: strainOfTarget, color: strainBlue, lineWidth: 9, inset: 24)
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                row(color: zoneColor(entry.zone), label: "Recovery",
                    value: entry.score.map { "\($0) %" } ?? "–")
                row(color: sleepPurple, label: widgetIsGerman ? "Schlaf" : "Sleep",
                    value: entry.sleepPerformance.map { "\(Int($0.rounded())) %" } ?? "–")
                row(color: strainBlue, label: "Strain",
                    value: strainText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(Color.black, for: .widget)
    }

    private var strainText: String {
        guard let strain = entry.strain else { return "–" }
        if let target = entry.strainTarget {
            return String(format: "%.1f / %.1f", strain, target)
        }
        return String(format: "%.1f", strain)
    }

    private func row(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

struct PulseOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseOverview", provider: PulseProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName(widgetIsGerman ? "Tages-Übersicht" : "Daily overview")
        .description(widgetIsGerman ? "Recovery, Schlaf und Strain (relativ zum Tagesziel) auf einen Blick." : "Recovery, sleep and strain (relative to daily target) at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Bundle

@main
struct PulseWidgets: WidgetBundle {
    var body: some Widget {
        PulseRecoveryWidget()
        PulseOverviewWidget()
    }
}

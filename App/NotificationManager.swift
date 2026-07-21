import Foundation
import UserNotifications

/// Lokale Benachrichtigungen (rein auf dem Gerät, kein Server):
/// – morgendliche Recovery-Zusammenfassung nach dem Hintergrund-Sync
/// – Warnung, bevor die Google-Verbindung im Testing-Modus (7 Tage) abläuft.
enum PulseNotifications {
    static let tokenExpiryID = "pulse.tokenExpiry"
    static let morningReminderID = "pulse.morningReminder"
    static let bedtimeID = "pulse.bedtime"

    private static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Morgendliche Zusammenfassung nach dem Hintergrund-Sync — nur echte,
    /// frisch berechnete Werte, nie geraten.
    static func postRecoverySummary(recovery: Int, sleep: String?, journalPending: Bool, alertMessage: String?) {
        let emoji = recovery >= 67 ? "🟢" : (recovery >= 34 ? "🟡" : "🔴")
        let content = UNMutableNotificationContent()
        content.title = "Recovery heute: \(recovery) % \(emoji)"
        var lines: [String] = []
        if let sleep { lines.append("Schlaf: \(sleep)") }
        if let alertMessage { lines.append("⚠️ \(alertMessage)") }
        if journalPending { lines.append("Journal für gestern noch offen – 10 Sekunden.") }
        content.body = lines.isEmpty ? "Tippe für deine Tagesübersicht." : lines.joined(separator: "\n")
        content.sound = .default
        // trigger nil = sofort ausliefern.
        let request = UNNotificationRequest(identifier: "pulse.recovery", content: content, trigger: nil)
        center.add(request)
    }

    /// Fallback-Wecker: feuert MORGEN 7:30, falls bis dahin kein Hintergrund-
    /// Sync lief (der ersetzt diese Planung bei jedem Lauf). So kommt morgens
    /// immer etwas — entweder echte Zahlen oder die Bitte, kurz zu öffnen.
    static func scheduleMorningReminder(hour: Int = 7, minute: Int = 30) {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = hour
        comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = "Guten Morgen ☀️"
        content.body = "Öffne Pulse kurz – dann stehen Recovery und Schlafanalyse für heute bereit."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // Gleiche ID ersetzt die bestehende Planung (auch die für heute).
        center.add(UNNotificationRequest(identifier: morningReminderID, content: content, trigger: trigger))
    }

    /// Abend-Erinnerung ~30 min vor der empfohlenen Zubettgehzeit (heute).
    static func scheduleBedtimeReminder(bedtimeMinutes: Double) {
        cancelBedtimeReminder()
        let cal = Calendar.current
        let m = (Int(bedtimeMinutes.rounded()) % 1440 + 1440) % 1440
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = m / 60
        comps.minute = m % 60
        guard var fireDate = cal.date(from: comps) else { return }
        fireDate = fireDate.addingTimeInterval(-30 * 60)
        // Nur planen, wenn die Zeit heute noch bevorsteht (Puffer 5 min).
        guard fireDate.timeIntervalSinceNow > 5 * 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Schlafenszeit rückt näher 🌙"
        content.body = "Ziel heute: bis \(Fmt.clockFromMinutes(bedtimeMinutes)) Uhr ins Bett für deine volle Erholung."
        content.sound = .default
        let fireComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: false)
        center.add(UNNotificationRequest(identifier: bedtimeID, content: content, trigger: trigger))
    }

    static func cancelBedtimeReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [bedtimeID])
    }

    /// Warnung ~6,5 Tage nach dem Verbinden (bevor das Refresh-Token abläuft).
    static func scheduleTokenExpiry(connectedAt: Date) {
        cancelTokenExpiry()
        let fireDate = connectedAt.addingTimeInterval(6.5 * 24 * 3600)
        guard fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Google-Verbindung läuft bald ab"
        content.body = "Im Testing-Modus alle 7 Tage. Öffne Pulse und tippe auf „Neu verbinden“."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: tokenExpiryID, content: content, trigger: trigger))
    }

    static func cancelTokenExpiry() {
        center.removePendingNotificationRequests(withIdentifiers: [tokenExpiryID])
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

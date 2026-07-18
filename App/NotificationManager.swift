import Foundation
import UserNotifications

/// Lokale Benachrichtigungen (rein auf dem Gerät, kein Server):
/// – morgendliche Recovery-Zusammenfassung nach dem Hintergrund-Sync
/// – Warnung, bevor die Google-Verbindung im Testing-Modus (7 Tage) abläuft.
enum PulseNotifications {
    static let tokenExpiryID = "pulse.tokenExpiry"

    private static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Sofortige Zusammenfassung (aus dem Hintergrund-Sync heraus aufgerufen).
    static func postRecoverySummary(recovery: Int, sleep: String?) {
        let emoji = recovery >= 67 ? "🟢" : (recovery >= 34 ? "🟡" : "🔴")
        let content = UNMutableNotificationContent()
        content.title = "Recovery heute: \(recovery) % \(emoji)"
        content.body = sleep.map { "Schlaf: \($0)" } ?? "Tippe für deine Tagesübersicht."
        content.sound = .default
        // trigger nil = sofort ausliefern.
        let request = UNNotificationRequest(identifier: "pulse.recovery", content: content, trigger: nil)
        center.add(request)
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

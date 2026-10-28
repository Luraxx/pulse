import Foundation
import WidgetKit

/// Schreibt einen kleinen Recovery-Snapshot in den geteilten App-Group-Container,
/// den das Widget liest. Bewusst nur Primitive (kein geteilter Typ nötig).
enum WidgetBridge {
    /// App Group, auf die dieses Build tatsächlich Zugriff hat. Xcode-Builds nutzen
    /// fest `group.net.dehlwes.pulse`. Sideloading-Tools signieren mit einer eigenen
    /// Gruppe unter dem Team des Nutzers neu: SideStore/AltStore tragen sie als
    /// `ALTAppGroups` in die Info.plist ein, iloader nimmt `group.<neue Bundle-ID>`.
    /// Gewählt wird der erste Kandidat, für den iOS einen Container herausgibt (das
    /// tut es nur mit passendem Entitlement). Gegenstück im Widget: `appGroup` in
    /// PulseWidget.swift, beide synchron halten.
    static let appGroup: String = {
        let fallback = "group.net.dehlwes.pulse"
        var candidates = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        candidates.append(fallback)
        if let bundleID = Bundle.main.bundleIdentifier {
            candidates.append("group." + bundleID)
        }
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? fallback
    }()

    enum Key {
        static let score = "recovery.score"
        static let zone = "recovery.zone"
        static let sleepPerformance = "sleep.performance"
        static let strain = "strain.value"
        static let strainTarget = "strain.target"
        static let updatedAt = "recovery.updatedAt"
        static let language = "app.language"
    }

    static func publish(
        recovery: RecoveryResult?,
        sleepPerformance: Double?,
        strain: Double?,
        strainTarget: Double?,
        language: PulseLanguage
    ) {
        // Nil, wenn die App-Group (noch) nicht bereitsteht → stiller No-Op.
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        if let recovery {
            defaults.set(recovery.score, forKey: Key.score)
            defaults.set(recovery.zone.rawValue, forKey: Key.zone)
        } else {
            defaults.removeObject(forKey: Key.score)
            defaults.removeObject(forKey: Key.zone)
        }
        setOrRemove(defaults, sleepPerformance, Key.sleepPerformance)
        setOrRemove(defaults, strain, Key.strain)
        setOrRemove(defaults, strainTarget, Key.strainTarget)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func setOrRemove(_ defaults: UserDefaults, _ value: Double?, _ key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

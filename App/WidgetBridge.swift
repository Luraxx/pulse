import Foundation
import WidgetKit

/// Schreibt einen kleinen Recovery-Snapshot in den geteilten App-Group-Container,
/// den das Widget liest. Bewusst nur Primitive (kein geteilter Typ nötig).
enum WidgetBridge {
    static let appGroup = "group.net.dehlwes.pulse"

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

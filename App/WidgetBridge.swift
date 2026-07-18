import Foundation
import WidgetKit

/// Schreibt einen kleinen Recovery-Snapshot in den geteilten App-Group-Container,
/// den das Widget liest. Bewusst nur Primitive (kein geteilter Typ nötig).
enum WidgetBridge {
    static let appGroup = "group.net.dehlwes.pulse"

    enum Key {
        static let score = "recovery.score"
        static let zone = "recovery.zone"
        static let updatedAt = "recovery.updatedAt"
    }

    static func publish(recovery: RecoveryResult?) {
        // Nil, wenn die App-Group (noch) nicht bereitsteht → stiller No-Op.
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        if let recovery {
            defaults.set(recovery.score, forKey: Key.score)
            defaults.set(recovery.zone.rawValue, forKey: Key.zone)
        } else {
            defaults.removeObject(forKey: Key.score)
            defaults.removeObject(forKey: Key.zone)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

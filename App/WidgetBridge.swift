import Foundation
import WidgetKit

/// Writes a small recovery snapshot into the shared App Group container,
/// which the widget reads. Intentionally primitives only (no shared type needed).
enum WidgetBridge {
    /// App Group this build actually has access to. Xcode builds always use
    /// `group.net.dehlwes.pulse`. Sideloading tools re-sign with their own
    /// group under the user's team: SideStore/AltStore add it as
    /// `ALTAppGroups` to the Info.plist, iloader uses `group.<new bundle ID>`.
    /// The first candidate for which iOS hands out a container is chosen (it
    /// only does so with a matching entitlement). Counterpart in the widget: `appGroup` in
    /// PulseWidget.swift, keep both in sync.
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
        // Nil if the App Group is not available (yet) → silent no-op.
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

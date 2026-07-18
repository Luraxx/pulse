import Foundation
import Observation
import AuthenticationServices

/// Zentrales App-Modell: hält Store, Auth, Einstellungen und die berechneten
/// Whoop-Metriken (Recovery, Strain, Schlaf) für alle Views bereit.
@MainActor
@Observable
final class AppModel {
    // MARK: - Einstellungen (in UserDefaults persistiert)

    private enum Keys {
        static let clientID = "google.clientID"
        static let onboarded = "app.onboarded"
        static let demoMode = "app.demoMode"
        static let daysBack = "sync.daysBack"
        static let hrDaysBack = "sync.hrDaysBack"
        static let sleepNeed = "calc.sleepNeedMinutes"
        static let age = "calc.age"
        static let sex = "calc.sex"
        static let maxHR = "calc.maxHROverride"
        static let lastSync = "sync.lastSyncAt"
    }

    var clientID: String {
        didSet { defaults.set(clientID, forKey: Keys.clientID) }
    }
    var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Keys.onboarded) }
    }
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Keys.demoMode) }
    }
    var daysBack: Int {
        didSet { defaults.set(daysBack, forKey: Keys.daysBack) }
    }
    var hrDaysBack: Int {
        didSet { defaults.set(hrDaysBack, forKey: Keys.hrDaysBack) }
    }
    var baseSleepNeedMinutes: Double {
        didSet {
            defaults.set(baseSleepNeedMinutes, forKey: Keys.sleepNeed)
            recomputeAll()
        }
    }
    var age: Int {
        didSet {
            defaults.set(age, forKey: Keys.age)
            recomputeAll()
        }
    }
    var sex: BiologicalSex {
        didSet {
            defaults.set(sex.rawValue, forKey: Keys.sex)
            recomputeAll()
        }
    }
    /// 0 = automatisch (Tanaka-Formel)
    var maxHROverride: Double {
        didSet {
            defaults.set(maxHROverride, forKey: Keys.maxHR)
            recomputeAll()
        }
    }
    var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                defaults.set(lastSyncAt.timeIntervalSince1970, forKey: Keys.lastSync)
            } else {
                defaults.removeObject(forKey: Keys.lastSync)
            }
        }
    }

    // MARK: - Laufzeit-Zustand

    private(set) var syncing = false
    private(set) var syncMessage = ""
    private(set) var syncFraction: Double = 0
    var lastError: String?
    private(set) var syncLog: [SyncLogEntry] = []
    var selectedDayKey: String
    private(set) var profileName: String?

    // MARK: - Daten & abgeleitete Metriken

    let store: MetricsStore
    let auth = GoogleAuth()
    private(set) var strainResults: [String: StrainResult] = [:]
    private(set) var sleepAnalyses: [String: SleepAnalysis] = [:]
    private(set) var recoveryResults: [String: RecoveryResult] = [:]
    private(set) var ageResults: [String: AgeResult] = [:]

    private let defaults = UserDefaults.standard

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        store = MetricsStore(directory: directory)

        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        onboarded = defaults.bool(forKey: Keys.onboarded)
        demoMode = defaults.bool(forKey: Keys.demoMode)
        daysBack = (defaults.object(forKey: Keys.daysBack) as? Int) ?? 60
        hrDaysBack = (defaults.object(forKey: Keys.hrDaysBack) as? Int) ?? 14
        baseSleepNeedMinutes = (defaults.object(forKey: Keys.sleepNeed) as? Double) ?? 456
        age = (defaults.object(forKey: Keys.age) as? Int) ?? 30
        sex = (defaults.string(forKey: Keys.sex)).flatMap(BiologicalSex.init(rawValue:)) ?? .unspecified
        maxHROverride = (defaults.object(forKey: Keys.maxHR) as? Double) ?? 0
        lastSyncAt = (defaults.object(forKey: Keys.lastSync) as? Double).map(Date.init(timeIntervalSince1970:))
        selectedDayKey = DayKey.today()

        recomputeAll()
    }

    // MARK: - Abgeleitete Konfiguration

    var oauthConfig: GoogleOAuthConfig {
        GoogleOAuthConfig(clientID: clientID)
    }

    var isConnected: Bool {
        auth.isConnected
    }

    var strainConfig: StrainConfig {
        StrainConfig(age: age, maxHROverride: maxHROverride > 0 ? maxHROverride : nil)
    }

    var sleepConfig: SleepEngineConfig {
        var config = SleepEngineConfig()
        config.baselineNeedMinutes = baseSleepNeedMinutes
        return config
    }

    var hasData: Bool {
        !store.days.isEmpty
    }

    var availableKeys: [String] {
        store.sortedKeys
    }

    // MARK: - Zugriff für Views

    func record(for key: String) -> DayRecord? {
        store.days[key]
    }

    func recovery(for key: String) -> RecoveryResult? {
        recoveryResults[key]
    }

    func sleep(for key: String) -> SleepAnalysis? {
        sleepAnalyses[key]
    }

    func strain(for key: String) -> StrainResult? {
        strainResults[key]
    }

    func ageResult(for key: String) -> AgeResult? {
        ageResults[key]
    }

    var selectedRecord: DayRecord? {
        record(for: selectedDayKey)
    }

    /// Health-Monitor-Status für den ausgewählten Tag.
    var healthStatuses: [HealthMetricStatus] {
        guard let record = selectedRecord else { return [] }
        let history = store.history(before: selectedDayKey, days: 45)
        return HealthMonitor.evaluate(today: record, history: history)
    }

    /// Werte einer Metrik der letzten `count` Tage bis zum ausgewählten Tag.
    func trend(_ count: Int, endingAt key: String? = nil, _ value: (DayRecord) -> Double?) -> [(key: String, value: Double)] {
        let end = key ?? selectedDayKey
        let start = DayKey.addDays(end, -(count - 1))
        return DayKey.keys(from: start, to: end).compactMap { dayKey in
            guard let record = store.days[dayKey], let v = value(record) else { return nil }
            return (dayKey, v)
        }
    }

    // MARK: - Neuberechnung

    func recomputeAll() {
        var strains: [String: StrainResult] = [:]
        var strainScalar: [String: Double] = [:]
        for (key, record) in store.days {
            let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
            strains[key] = result
            strainScalar[key] = result.strain
        }
        strainResults = strains

        sleepAnalyses = SleepEngine.analyze(days: store.days, config: sleepConfig, strainByDay: strainScalar)

        // Workout-Strains in die Records schreiben
        for (_, record) in store.days where !record.workouts.isEmpty {
            var updated = record
            for index in updated.workouts.indices {
                updated.workouts[index].strain = StrainEngine.workoutStrain(
                    workout: updated.workouts[index],
                    daySamples: record.hrSamples,
                    restingHR: record.restingHR,
                    config: strainConfig
                )
            }
            store.upsert(updated)
        }

        // Recovery chronologisch mit wachsender Historie
        var recoveries: [String: RecoveryResult] = [:]
        var history: [DayRecord] = []
        let keys = store.sortedKeys
        history.reserveCapacity(keys.count)
        for key in keys {
            guard let record = store.days[key] else { continue }
            recoveries[key] = RecoveryEngine.compute(
                dateKey: key,
                today: record,
                history: history,
                sleepPerformance: sleepAnalyses[key]?.performance
            )
            history.append(record)
        }
        recoveryResults = recoveries

        // Biologisches „Pulse Alter" je Tag aus dem 30-Tage-Fenster.
        var ages: [String: AgeResult] = [:]
        for key in keys {
            let window = store.chronological(upTo: key, count: AgeEngine.calibrationNeed)
            guard !window.isEmpty else { continue }
            let sleepPerf = window.compactMap { record -> Double? in
                guard let analysis = sleepAnalyses[record.date], analysis.hasData else { return nil }
                return analysis.performance
            }
            let inputs = AgeInputs(
                chronoAge: age,
                sex: sex,
                vo2maxValues: window.compactMap { $0.vo2max },
                rmssdValues: window.compactMap { $0.hrvRmssd },
                restingHRValues: window.compactMap { $0.restingHR },
                observedMaxHR: Self.robustMaxHR(window),
                maxHROverride: maxHROverride > 0 ? maxHROverride : nil,
                sleepPerformances: sleepPerf,
                stepsValues: window.compactMap { $0.steps.map(Double.init) },
                validDayCount: window.filter { $0.hrvRmssd != nil || $0.restingHR != nil }.count
            )
            ages[key] = AgeEngine.compute(dateKey: key, inputs: inputs)
        }
        ageResults = ages

        if store.days[selectedDayKey] == nil, let last = keys.last {
            selectedDayKey = last
        }
    }

    /// Robuster beobachteter Maxpuls (97,5. Perzentil) über die Intraday-HF des
    /// Fensters; nil bei zu wenig Samples (verhindert Artefakt-Ausreißer).
    private static func robustMaxHR(_ window: [DayRecord]) -> Double? {
        let bpms = window.flatMap { $0.hrSamples.map(\.bpm) }
        guard bpms.count >= 300 else { return nil }
        return Stats.percentile(bpms, 0.975)
    }

    // MARK: - Aktionen

    func startDemo() {
        store.replaceAll(DemoData.generate(daysBack: 120, seed: 42))
        store.save()
        demoMode = true
        onboarded = true
        selectedDayKey = DayKey.today()
        lastError = nil
        recomputeAll()
    }

    func connect() async {
        lastError = nil
        let config = oauthConfig
        guard config.isValid, let scheme = config.reversedClientScheme else {
            lastError = AuthError.invalidClientID.errorDescription
            return
        }
        let pkce = PKCE()
        let state = UUID().uuidString
        guard let url = auth.authorizationURL(config: config, pkce: pkce, state: state) else {
            lastError = "Autorisierungs-URL konnte nicht erstellt werden."
            return
        }
        do {
            let callback = try await WebAuthenticator.shared.authenticate(url: url, callbackScheme: scheme)
            guard let code = GoogleAuth.extractCode(from: callback, expectedState: state) else {
                lastError = "Kein gültiger Autorisierungscode erhalten."
                return
            }
            _ = try await auth.exchange(code: code, pkce: pkce, config: config)
            if demoMode {
                store.wipe()
                demoMode = false
            }
            onboarded = true
            recomputeAll()
            await syncNow()
        } catch let error as AuthError {
            lastError = error.errorDescription
        } catch {
            let nsError = error as NSError
            let cancelled = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            if !cancelled {
                lastError = error.localizedDescription
            }
        }
    }

    func syncNow() async {
        guard !syncing else { return }
        guard isConnected else {
            lastError = AuthError.notConnected.errorDescription
            return
        }
        syncing = true
        syncMessage = "Starte…"
        syncFraction = 0
        defer { syncing = false }

        let client = HealthAPIClient(auth: auth, config: oauthConfig)
        let engine = SyncEngine(client: client)
        let outcome = await engine.sync(
            existingDays: store.days,
            daysBack: daysBack,
            hrDaysBack: hrDaysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = progress.fraction
            }
        }

        store.replaceAll(outcome.updatedDays)
        store.save()
        syncLog = outcome.log
        lastSyncAt = Date()
        profileName = outcome.profile?.displayName ?? profileName
        if sex == .unspecified, let profileSex = outcome.profile?.sex, profileSex != .unspecified {
            sex = profileSex // löst recomputeAll() aus
        } else {
            recomputeAll()
        }

        if outcome.hadErrors {
            lastError = "Sync mit Warnungen abgeschlossen – Details im Sync-Protokoll."
        }
    }

    func disconnect() {
        auth.disconnect()
    }

    func resetAll() {
        store.wipe()
        syncLog = []
        lastSyncAt = nil
        demoMode = false
        onboarded = false
        profileName = nil
        lastError = nil
        recomputeAll()
    }
}

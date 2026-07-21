import Foundation
import Observation
import AuthenticationServices
import BackgroundTasks
import UIKit

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
        static let heightCm = "profile.heightCm"
        static let weightKg = "profile.weightKg"
        static let maxHR = "calc.maxHROverride"
        static let lastSync = "sync.lastSyncAt"
        static let notifications = "notify.enabled"
        static let connectedAt = "auth.connectedAt"
        static let moduleOrder = "dashboard.moduleOrder"
        static let hiddenModules = "dashboard.hiddenModules"
        static let language = "app.language"
    }

    /// Identifier des Hintergrund-Sync-Tasks (muss in Info.plist unter
    /// BGTaskSchedulerPermittedIdentifiers stehen).
    static let refreshTaskID = "net.dehlwes.pulse.refresh"

    /// App-Sprache; wirkt sofort auf alle Texte (kein Neustart nötig).
    var language: PulseLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            Fmt.language = language
            recomputeAll() // AgeEngine-Komponenten tragen lokalisierte Texte
        }
    }

    /// Kurzform für zweisprachige Texte direkt am Verwendungsort.
    func loc(_ de: String, _ en: String) -> String {
        language == .de ? de : en
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
    /// Körpergröße in cm (Profil; fließt aktuell in keine Score-Berechnung ein).
    var heightCm: Double {
        didSet { defaults.set(heightCm, forKey: Keys.heightCm) }
    }
    /// Gewicht in kg (Profil; VO₂max ist bereits pro kg normalisiert).
    var weightKg: Double {
        didSet { defaults.set(weightKg, forKey: Keys.weightKg) }
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
    /// Opt-in für morgendliche Recovery-Benachrichtigung + Hintergrund-Sync.
    private(set) var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    /// Zeitpunkt der letzten Verbindung (für die 7-Tage-Ablaufwarnung).
    private(set) var connectedAt: Date? {
        didSet {
            if let connectedAt {
                defaults.set(connectedAt.timeIntervalSince1970, forKey: Keys.connectedAt)
            } else {
                defaults.removeObject(forKey: Keys.connectedAt)
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
    /// Tag, für den das Morgen-Journal-Popup gezeigt werden soll (i. d. R. gestern).
    var journalPromptDay: String?

    // MARK: - Dashboard-Anpassung

    /// Reihenfolge ALLER Module (auch ausgeblendeter).
    private(set) var moduleOrder: [DashboardModule] = DashboardModule.allCases {
        didSet { defaults.set(moduleOrder.map(\.rawValue), forKey: Keys.moduleOrder) }
    }
    /// Ausgeblendete Module.
    private(set) var hiddenModules: Set<DashboardModule> = [] {
        didSet { defaults.set(hiddenModules.map(\.rawValue), forKey: Keys.hiddenModules) }
    }

    var visibleModules: [DashboardModule] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
    }

    func setModule(_ module: DashboardModule, visible: Bool) {
        if visible {
            hiddenModules.remove(module)
        } else {
            hiddenModules.insert(module)
        }
    }

    // MARK: - Daten & abgeleitete Metriken

    let store: MetricsStore
    let journal: JournalStore
    let auth = GoogleAuth()
    private(set) var strainResults: [String: StrainResult] = [:]
    private(set) var sleepAnalyses: [String: SleepAnalysis] = [:]
    private(set) var recoveryResults: [String: RecoveryResult] = [:]
    private(set) var ageResults: [String: AgeResult] = [:]
    private(set) var journalInsights: [FactorInsight] = []

    private let defaults = UserDefaults.standard

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        store = MetricsStore(directory: directory)
        journal = JournalStore(directory: directory)

        // Lokale Konstante, damit unten nicht self.language (Observable-Getter)
        // gelesen wird, bevor alle Stored Properties initialisiert sind.
        let initialLanguage = defaults.string(forKey: Keys.language).flatMap(PulseLanguage.init(rawValue:))
            ?? .systemDefault
        language = initialLanguage
        Fmt.language = initialLanguage

        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        onboarded = defaults.bool(forKey: Keys.onboarded)
        demoMode = defaults.bool(forKey: Keys.demoMode)
        daysBack = (defaults.object(forKey: Keys.daysBack) as? Int) ?? 60
        hrDaysBack = (defaults.object(forKey: Keys.hrDaysBack) as? Int) ?? 14
        baseSleepNeedMinutes = (defaults.object(forKey: Keys.sleepNeed) as? Double) ?? 456
        age = (defaults.object(forKey: Keys.age) as? Int) ?? 30
        sex = (defaults.string(forKey: Keys.sex)).flatMap(BiologicalSex.init(rawValue:)) ?? .unspecified
        heightCm = (defaults.object(forKey: Keys.heightCm) as? Double) ?? 175
        weightKg = (defaults.object(forKey: Keys.weightKg) as? Double) ?? 75
        maxHROverride = (defaults.object(forKey: Keys.maxHR) as? Double) ?? 0
        lastSyncAt = (defaults.object(forKey: Keys.lastSync) as? Double).map(Date.init(timeIntervalSince1970:))
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        connectedAt = (defaults.object(forKey: Keys.connectedAt) as? Double).map(Date.init(timeIntervalSince1970:))
        selectedDayKey = DayKey.today()

        // Modul-Reihenfolge laden; neue Module (künftiger Versionen) hinten anfügen.
        var order = (defaults.stringArray(forKey: Keys.moduleOrder) ?? [])
            .compactMap(DashboardModule.init(rawValue:))
        for module in DashboardModule.allCases where !order.contains(module) {
            order.append(module)
        }
        moduleOrder = order
        hiddenModules = Set(
            (defaults.stringArray(forKey: Keys.hiddenModules) ?? [])
                .compactMap(DashboardModule.init(rawValue:))
        )

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

    // MARK: - Journal

    func journalEntry(for key: String) -> JournalEntry {
        journal.entry(for: key)
    }

    func toggleJournal(_ factor: JournalFactor, on key: String) {
        journal.toggle(factor, on: key)
        journal.save()
        recomputeJournalInsights()
    }

    private func recomputeJournalInsights() {
        let recoveryByDay = recoveryResults.mapValues { $0.score }
        journalInsights = JournalEngine.insights(entries: journal.entries, recoveryByDay: recoveryByDay)
    }

    /// Anzahl Tage mit Recovery — Grundlage für die Monats-Auswertung (ab 28).
    var recoveryDayCount: Int {
        recoveryResults.count
    }

    /// Zeigt das Journal-Popup für gestern — höchstens 1× pro Tag, nur wenn
    /// gestern Daten hat und noch nichts eingetragen wurde.
    func maybeShowJournalPrompt() {
        guard hasData, journalPromptDay == nil else { return }
        let yesterday = DayKey.addDays(DayKey.today(), -1)
        guard journal.entry(for: yesterday).factors.isEmpty,
              let record = store.days[yesterday],
              record.restingHR != nil || !record.sleepSessions.isEmpty || record.steps != nil else { return }
        let promptedKey = "journal.promptedFor"
        guard defaults.string(forKey: promptedKey) != yesterday else { return }
        defaults.set(yesterday, forKey: promptedKey)
        journalPromptDay = yesterday
    }

    /// Plant die Routine-Benachrichtigungen neu (nach jedem Sync):
    /// Morgen-Wecker für morgen 7:30 (ersetzt den heutigen) und die
    /// Zubettgeh-Erinnerung für heute Abend.
    func rescheduleRoutineNotifications() {
        guard notificationsEnabled else { return }
        PulseNotifications.scheduleMorningReminder(language: language)
        if let bed = bedtimeTonight?.recommendedBedtimeMinutes {
            PulseNotifications.scheduleBedtimeReminder(bedtimeMinutes: bed, language: language)
        } else {
            PulseNotifications.cancelBedtimeReminder()
        }
    }

    // MARK: - Health-Warnung & Zubettgeh-Empfehlung

    /// Proaktive Gesundheitswarnung für den ausgewählten Tag (nil = alles im Rahmen).
    var healthAlert: HealthAlert? {
        let records = store.chronological(upTo: selectedDayKey, count: 10)
        return HealthMonitor.alert(records: records, language: language)
    }

    /// Empfehlung für die kommende Nacht (aus Schlafschuld, heutigem Strain,
    /// gewohnter Aufwachzeit). nil ohne genug Historie.
    var bedtimeTonight: BedtimeRecommendation? {
        guard hasData else { return nil }
        let today = DayKey.today()
        let debt = sleepAnalyses[today]?.debtAfterMinutes
            ?? store.sortedKeys.last.flatMap { sleepAnalyses[$0]?.debtAfterMinutes }
            ?? 0
        let strainToday = strainResults[today]?.strain ?? 0
        let recentWakes = store.chronological(upTo: today, count: 7)
            .compactMap { sleepAnalyses[$0.date]?.wakeTime }
        guard !recentWakes.isEmpty else { return nil }
        return SleepEngine.bedtimeRecommendation(
            currentDebtMinutes: debt,
            strainToday: strainToday,
            recentWakeTimes: recentWakes,
            config: sleepConfig
        )
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
        recomputeJournalInsights()

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
            ages[key] = AgeEngine.compute(dateKey: key, inputs: inputs, language: language)
        }
        ageResults = ages

        if store.days[selectedDayKey] == nil, let last = keys.last {
            selectedDayKey = last
        }

        // Tages-Snapshot für die Widgets aktualisieren.
        let today = DayKey.today()
        let todayRecovery = recoveryResults[today]
        let todaySleep = sleepAnalyses[today]
        WidgetBridge.publish(
            recovery: todayRecovery,
            sleepPerformance: (todaySleep?.hasData == true) ? todaySleep?.performance : nil,
            strain: strainResults[today]?.strain,
            strainTarget: todayRecovery.map { StrainEngine.targetStrain(forRecovery: $0.score) },
            language: language
        )
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
            connectedAt = Date()
            if notificationsEnabled, let connectedAt {
                PulseNotifications.scheduleTokenExpiry(connectedAt: connectedAt, language: language)
                scheduleBackgroundRefresh()
            }
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

    func syncNow(daysBackOverride: Int? = nil, hrDaysBackOverride: Int? = nil) async {
        guard !syncing else { return }
        guard isConnected else {
            lastError = AuthError.notConnected.errorDescription
            return
        }
        syncing = true
        syncMessage = "Starte…"
        syncFraction = 0

        // Sync gegen Display-Sperre absichern und beim App-Wechsel noch
        // ~30 s im Hintergrund weiterlaufen lassen (Teilergebnisse werden
        // ohnehin nach jeder Phase gespeichert).
        UIApplication.shared.isIdleTimerDisabled = true
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "pulse.sync") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            syncing = false
            UIApplication.shared.isIdleTimerDisabled = false
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }

        let client = HealthAPIClient(auth: auth, config: oauthConfig)
        let engine = SyncEngine(client: client)

        // Phase 1: alle Tagesmetriken — danach sofort speichern und anzeigen.
        let daily = await engine.syncDailyMetrics(
            existingDays: store.days,
            daysBack: daysBackOverride ?? daysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = progress.fraction * 0.55
            }
        }
        store.replaceAll(daily.updatedDays)
        store.save()
        syncLog = daily.log
        profileName = daily.profile?.displayName ?? profileName
        if sex == .unspecified, let profileSex = daily.profile?.sex, profileSex != .unspecified {
            sex = profileSex // löst recomputeAll() aus
        } else {
            recomputeAll()
        }

        // Phase 2: Intraday-Herzfrequenz — nur fehlende Tage, parallel.
        let hr = await engine.syncIntradayHeartRate(
            existingDays: store.days,
            hrDaysBack: hrDaysBackOverride ?? hrDaysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = 0.55 + progress.fraction * 0.45
            }
        }
        store.replaceAll(hr.updatedDays)
        store.save()
        syncLog = daily.log + hr.log
        lastSyncAt = Date()
        recomputeAll()

        if daily.hadErrors || hr.hadErrors {
            lastError = "Sync mit Warnungen abgeschlossen – Details im Sync-Protokoll."
        }

        rescheduleRoutineNotifications()
        maybeShowJournalPrompt()
    }

    func disconnect() {
        auth.disconnect()
        connectedAt = nil
        PulseNotifications.cancelTokenExpiry()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
    }

    func resetAll() {
        store.wipe()
        journal.wipe()
        syncLog = []
        lastSyncAt = nil
        connectedAt = nil
        demoMode = false
        onboarded = false
        profileName = nil
        lastError = nil
        PulseNotifications.cancelAll()
        recomputeAll()
    }

    // MARK: - Benachrichtigungen & Hintergrund-Sync

    func setNotifications(enabled: Bool) async {
        if enabled {
            let granted = await PulseNotifications.requestAuthorization()
            notificationsEnabled = granted
            if granted {
                if let connectedAt { PulseNotifications.scheduleTokenExpiry(connectedAt: connectedAt, language: language) }
                scheduleBackgroundRefresh()
            }
        } else {
            notificationsEnabled = false
            PulseNotifications.cancelAll()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        }
    }

    /// Plant den nächsten Hintergrund-Sync. iOS entscheidet über den realen
    /// Zeitpunkt – „ab früh morgens" ist nur ein Wunsch, keine Garantie.
    func scheduleBackgroundRefresh() {
        guard notificationsEnabled, isConnected else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Self.nextEarlyMorning()
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Aufgerufen vom `.backgroundTask`-Handler: leichter Sync + Morgen-Notification.
    func performBackgroundRefresh() async {
        scheduleBackgroundRefresh() // sofort den nächsten Lauf einplanen
        guard isConnected else { return }
        await syncNow(daysBackOverride: 3, hrDaysBackOverride: 1)
        guard notificationsEnabled, await PulseNotifications.isAuthorized() else { return }
        let today = DayKey.today()
        if let rec = recovery(for: today) {
            let sleepText = sleep(for: today).flatMap { $0.hasData ? "\(Fmt.hm($0.sleptMinutes)) h" : nil }
            let yesterday = DayKey.addDays(today, -1)
            let journalPending = journal.entry(for: yesterday).factors.isEmpty && store.days[yesterday] != nil
            let alertMessage = HealthMonitor.alert(records: store.chronological(upTo: today, count: 10), language: language)?.message
            PulseNotifications.postRecoverySummary(
                recovery: rec.score,
                sleep: sleepText,
                journalPending: journalPending,
                alertMessage: alertMessage,
                language: language
            )
        }
    }

    private static func nextEarlyMorning(hour: Int = 6, minute: Int = 30) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        let target = cal.date(from: comps) ?? now.addingTimeInterval(6 * 3600)
        return target > now ? target : (cal.date(byAdding: .day, value: 1, to: target) ?? now.addingTimeInterval(6 * 3600))
    }
}

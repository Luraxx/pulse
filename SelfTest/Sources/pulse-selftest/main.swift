import Foundation
import PulseCore

// Self-Test-Runner: verifiziert die Core-Logik ohne Xcode/iOS-SDK.

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        print("  ✗ FEHLER: \(message)")
        failures.append(message)
    }
}

func section(_ name: String) {
    print("\n— \(name)")
}

func jsonDict(_ raw: String) -> [String: Any] {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        failures.append("Fixture nicht parsebar")
        return [:]
    }
    return dict
}

// MARK: PKCE (RFC-7636-Testvektor)

section("PKCE")
let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
check(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "SHA256-Challenge entspricht RFC-7636-Vektor")
let freshPKCE = PKCE()
check(freshPKCE.verifier.count >= 43, "Zufälliger Verifier hat ausreichende Länge")
check(freshPKCE.verifier != PKCE().verifier, "Verifier sind zufällig")

// MARK: OAuth-Konfiguration

section("OAuth-Konfiguration")
let config = GoogleOAuthConfig(clientID: "407408718192-abc123.apps.googleusercontent.com")
check(config.reversedClientScheme == "com.googleusercontent.apps.407408718192-abc123", "Reversed-Client-Schema korrekt")
check(config.redirectURI == "com.googleusercontent.apps.407408718192-abc123:/oauth2redirect", "Redirect-URI korrekt")
check(!GoogleOAuthConfig(clientID: "kaputt").isValid, "Ungültige Client-ID wird erkannt")

let auth = GoogleAuth(usesKeychain: false)
if let url = auth.authorizationURL(config: config, pkce: pkce, state: "test-state") {
    let absolute = url.absoluteString
    check(absolute.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth"), "Auth-URL zeigt auf Google")
    check(absolute.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"), "Auth-URL enthält PKCE-Challenge")
    check(absolute.contains("googlehealth.sleep.readonly"), "Auth-URL enthält Health-Scopes")
    check(!absolute.contains("prompt="), "Kein prompt=consent (Google-Health-Empfehlung)")
} else {
    check(false, "Auth-URL konnte nicht gebaut werden")
}
let callback = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=test-state&code=4/abc")!
check(GoogleAuth.extractCode(from: callback, expectedState: "test-state") == "4/abc", "Code-Extraktion aus Callback")
check(GoogleAuth.extractCode(from: callback, expectedState: "falsch") == nil, "State-Mismatch wird abgelehnt")
check(GoogleAuth.formEncode(["a": "b c", "x": "y+z"]) == "a=b%20c&x=y%2Bz", "Form-Encoding percent-encodiert korrekt")

// MARK: JSON-Extraktion (Google-Health-Formate)

section("JSON-Extraktion")
check(JSONExtract.snakeCase("heartRateVariability") == "heart_rate_variability", "camelCase → snake_case")

let hrPoint = jsonDict(#"""
{
  "dataSource": { "device": { "displayName": "Fitbit Air" }, "platform": "FITBIT", "recordingMethod": "DERIVED" },
  "heartRate": { "sampleTime": { "physicalTime": "2026-05-12T15:59:07Z" }, "beatsPerMinute": 72 }
}
"""#)
let hrPayload = (hrPoint["heartRate"] as? [String: Any]) ?? [:]
check(JSONExtract.firstDouble(in: hrPayload, keys: ["beatsPerMinute", "bpm"]) == 72, "Herzfrequenz-Wert extrahiert")
check(JSONExtract.firstDate(in: hrPayload, keys: ["physicalTime"]) != nil, "Sample-Zeit extrahiert (verschachtelt)")

let civil = JSONExtract.civilDateString(from: ["year": 2026, "month": 7, "day": 5])
check(civil == "2026-07-05", "CivilDate-Objekt → yyyy-MM-dd")

let sleepPoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/sleep/dataPoints/abc",
  "sleep": {
    "type": "STAGES",
    "interval": { "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T06:30:00Z" },
    "stages": [
      { "type": "LIGHT", "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T00:10:00Z" },
      { "type": "DEEP", "startTime": "2026-07-17T00:10:00Z", "endTime": "2026-07-17T01:20:00Z" },
      { "type": "REM", "startTime": "2026-07-17T01:20:00Z", "endTime": "2026-07-17T02:00:00Z" },
      { "type": "AWAKE", "startTime": "2026-07-17T02:00:00Z", "endTime": "2026-07-17T02:08:00Z" },
      { "type": "LIGHT", "startTime": "2026-07-17T02:08:00Z", "endTime": "2026-07-17T06:30:00Z" }
    ],
    "summary": { "minutesAsleep": 457, "minutesAwake": 8, "stagesSummary": [ { "type": "DEEP", "minutes": 70 } ] }
  }
}
"""#)
if let session = HealthAPIClient.parseSleep(sleepPoint) {
    check(session.stages.count == 5, "5 Schlafphasen dekodiert")
    check(session.minutesAsleep == 457, "minutesAsleep aus Summary übernommen")
    check(session.stages[1].stage == .deep, "DEEP → .deep gemappt")
    check(abs(session.minutesInBed - 465) < 0.01, "Zeit im Bett = 465 min")
} else {
    check(false, "Schlaf-Fixture konnte nicht dekodiert werden")
}
check(HealthAPIClient.parseSleep(["sleep": ["interval": [:]]]) == nil, "Unvollständige Schlafdaten → nil statt Absturz")

// Exercise: Google nennt das Zeitintervall "interval" (Filter interval.civil_start_time).
let exercisePoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/exercise/dataPoints/xyz",
  "exercise": {
    "exerciseType": "RUNNING",
    "activityName": "Laufen",
    "interval": { "startTime": "2026-07-17T17:30:00Z", "endTime": "2026-07-17T18:15:00Z" },
    "averageHeartRate": 148,
    "calories": 430
  }
}
"""#)
if let workout = HealthAPIClient.parseExercise(exercisePoint) {
    check(workout.name == "Laufen", "Workout-Name aus activityName")
    check(abs(workout.durationMinutes - 45) < 0.01, "Workout-Dauer aus interval = 45 min")
    check(workout.averageHR == 148, "Ø-Puls des Workouts dekodiert")
} else {
    check(false, "Exercise-Fixture mit interval konnte nicht dekodiert werden")
}
// Ältere/alternative Struktur "sessionTimeInterval" bleibt als Fallback lesbar.
let exerciseAlt = jsonDict(#"""
{ "exercise": { "activityName": "Rad", "sessionTimeInterval": { "startTime": "2026-07-17T08:00:00Z", "endTime": "2026-07-17T08:30:00Z" } } }
"""#)
check(HealthAPIClient.parseExercise(exerciseAlt)?.name == "Rad", "Fallback sessionTimeInterval bleibt lesbar")
check(HealthAPIClient.parseExercise(["exercise": ["interval": [:]]]) == nil, "Unvollständiges Workout → nil statt Absturz")

// MARK: DayKey

section("DayKey")
check(DayKey.addDays("2026-07-18", -1) == "2026-07-17", "addDays über Tagesgrenze")
check(DayKey.keys(from: "2026-02-27", to: "2026-03-02").count == 4, "Schaltjahr-Bereich (2026 kein Schaltjahr): 27.2.–2.3. = 4 Tage")
check(DayKey.distance(from: "2026-07-01", to: "2026-07-18") == 17, "Distanz zwischen Keys")
if let lateEvening = DayKey.date(from: "2026-07-17")?.addingTimeInterval(23 * 3600) {
    check(DayKey.nightKey(for: lateEvening) == "2026-07-18", "23-Uhr-Sample zählt zur Nacht des Folgetags")
}
if let earlyMorning = DayKey.date(from: "2026-07-18")?.addingTimeInterval(5 * 3600) {
    check(DayKey.nightKey(for: earlyMorning) == "2026-07-18", "5-Uhr-Sample zählt zum selben Tag")
}

// MARK: Statistik

section("Statistik")
check(Stats.percentile([1, 2, 3, 4, 5], 0.5) == 3, "Median")
check(Stats.percentile([10], 0.05) == 10, "Perzentil mit einem Wert")
check(abs(Stats.logistic(0) - 0.5) < 1e-9, "Logistic(0) = 0.5")
if let baseline = Stats.baseline([60, 62, 64, 66, 68]) {
    check(abs(baseline.mean - 64) < 1e-9, "Baseline-Mittelwert")
    check(baseline.isReliable, "5 Werte gelten als belastbar")
    check(abs(baseline.z(64)) < 1e-9, "z-Score am Mittelwert = 0")
} else {
    check(false, "Baseline nil trotz 5 Werten")
}
check(Stats.baseline([1, 2]) == nil, "Baseline braucht mindestens 3 Werte")

// MARK: Strain-Engine

section("Strain-Engine")
check(StrainEngine.strain(fromRaw: 0) == 0, "Kein Load → Strain 0")
let s60 = StrainEngine.strain(fromRaw: 60)
let s300 = StrainEngine.strain(fromRaw: 300)
let s900 = StrainEngine.strain(fromRaw: 900)
let s5000 = StrainEngine.strain(fromRaw: 5000)
check(s60 > 2 && s60 < 4, "Lockerer Tag ≈ 2–4 (ist \(String(format: "%.1f", s60)))")
check(s300 > 9 && s300 < 12, "Solides Training ≈ 9–12 (ist \(String(format: "%.1f", s300)))")
check(s900 > 16 && s900 < 19, "Harter Tag ≈ 16–19 (ist \(String(format: "%.1f", s900)))")
check(s5000 < 21, "Skala bleibt unter 21 (ist \(String(format: "%.2f", s5000)))")
check(s60 < s300 && s300 < s900 && s900 < s5000, "Strain wächst monoton mit Load")
check(StrainEngine.zoneIndex(for: 0.1) == nil, "Unter Zone 0 → kein Load")
check(StrainEngine.zoneIndex(for: 0.5) == 2, "50 % HRR → Zone 3 (Index 2)")
check(StrainEngine.zoneIndex(for: 0.99) == 5, "99 % HRR → Maximal-Zone")

// Ruhezeit: Samples nahe Ruhepuls erzeugen keine aktive Zonenzeit, aber restMin.
let strainBase = DayKey.date(from: "2026-07-17")!
let restSamples = (0..<10).map { HRSample(t: strainBase.addingTimeInterval(Double($0) * 60), bpm: 60) }
let restAcc = StrainEngine.accumulate(samples: restSamples, restingHR: 58, maxHR: 190)
check(restAcc.zones.reduce(0, +) == 0, "Ruhepuls-nahe Samples → keine aktive Zonenzeit")
check(restAcc.restMin >= 9, "Ruhezeit wird erfasst (\(Int(restAcc.restMin)) min)")
let restResult = StrainEngine.dayStrain(
    record: { var r = DayRecord(date: "2026-07-17"); r.hrSamples = restSamples; return r }(),
    restingHR: 58,
    config: StrainConfig(age: 30)
)
check(restResult.strain < 1, "Reiner Ruhetag → Strain nahe 0")
check(restResult.trackedMinutes >= 9, "Aufgezeichnete Zeit (Ruhe+aktiv) sichtbar")

// MARK: Demo-Daten + Engines Ende-zu-Ende

section("Demo-Daten & Engines")
let demoDays = DemoData.generate(daysBack: 120, seed: 42)
check(demoDays.count == 120, "120 Demo-Tage erzeugt")
let sortedKeys = demoDays.keys.sorted()

let strainConfig = StrainConfig(age: 30)
var strainByDay: [String: Double] = [:]
for (key, record) in demoDays {
    let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
    strainByDay[key] = result.strain
    if result.strain < 0 || result.strain > 21 {
        check(false, "Strain außerhalb 0–21 an \(key): \(result.strain)")
    }
}
check(strainByDay.values.allSatisfy { $0 >= 0 && $0 <= 21 }, "Alle Tages-Strains in 0–21")
let maxStrain = strainByDay.values.max() ?? 0
let avgStrain = strainByDay.values.reduce(0, +) / Double(strainByDay.count)
check(maxStrain > 10, "Harte Tage erreichen Strain > 10 (max \(String(format: "%.1f", maxStrain)))")
check(avgStrain > 3 && avgStrain < 16, "Durchschnitts-Strain plausibel (\(String(format: "%.1f", avgStrain)))")

let sleepConfig = SleepEngineConfig()
let sleepAnalyses = SleepEngine.analyze(days: demoDays, config: sleepConfig, strainByDay: strainByDay)
check(sleepAnalyses.count == 120, "Schlafanalyse für alle Tage")
for (key, analysis) in sleepAnalyses {
    if analysis.needMinutes < 300 || analysis.needMinutes > 620 {
        check(false, "Schlafbedarf außerhalb Plausibilität an \(key): \(analysis.needMinutes)")
    }
    if analysis.debtAfterMinutes < 0 || analysis.debtAfterMinutes > sleepConfig.maxDebtMinutes {
        check(false, "Schlafschuld außerhalb Grenzen an \(key)")
    }
    if let consistency = analysis.consistency, consistency < 0 || consistency > 100 {
        check(false, "Konsistenz außerhalb 0–100 an \(key)")
    }
    if analysis.performance < 0 || analysis.performance > 100 {
        check(false, "Schlafperformance außerhalb 0–100 an \(key)")
    }
}
check(true, "Bedarf/Schuld/Konsistenz/Performance in gültigen Bereichen")
let withStages = sleepAnalyses.values.filter { !$0.stageMinutes.isEmpty }
check(withStages.count == 120, "Alle Nächte haben Phasen-Minuten")

var recoveryScores: [Int] = []
for key in sortedKeys.suffix(60) {
    guard let record = demoDays[key] else { continue }
    let history = sortedKeys.filter { $0 < key }.compactMap { demoDays[$0] }
    let result = RecoveryEngine.compute(
        dateKey: key,
        today: record,
        history: history,
        sleepPerformance: sleepAnalyses[key]?.performance
    )
    if let result {
        recoveryScores.append(result.score)
        if result.score < 1 || result.score > 99 {
            check(false, "Recovery außerhalb 1–99 an \(key): \(result.score)")
        }
        let expectedZone: RecoveryZone = result.score >= 67 ? .green : (result.score >= 34 ? .yellow : .red)
        if result.zone != expectedZone {
            check(false, "Zonen-Mapping falsch an \(key)")
        }
        let weightSum = result.components.reduce(0) { $0 + $1.weight }
        if abs(weightSum - 1) > 0.001 {
            check(false, "Komponenten-Gewichte summieren nicht auf 1 an \(key)")
        }
    } else {
        check(false, "Recovery nil trotz Daten an \(key)")
    }
}
check(recoveryScores.count == 60, "Recovery für die letzten 60 Tage berechnet")
let recoveryRange = (recoveryScores.min() ?? 0)...(recoveryScores.max() ?? 0)
check(recoveryRange.upperBound - recoveryRange.lowerBound >= 20, "Recovery streut realistisch (\(recoveryRange))")

if let lastKey = sortedKeys.last, let lastRecord = demoDays[lastKey] {
    let history = sortedKeys.dropLast().compactMap { demoDays[$0] }
    let statuses = HealthMonitor.evaluate(today: lastRecord, history: Array(history))
    check(statuses.count == HealthMetricKind.allCases.count, "Health-Monitor liefert alle Metriken")
    check(statuses.allSatisfy { $0.state != .noData }, "Demo-Daten: keine Metrik ohne Daten")
    let rhrStatus = statuses.first { $0.kind == .restingHR }
    check(rhrStatus?.lowerBound != nil && rhrStatus?.upperBound != nil, "Ruhepuls hat Baseline-Band")
}

// MARK: Workout-Strain

section("Workout-Strain")
var workoutStrainChecked = false
for key in sortedKeys.suffix(28) {
    guard let record = demoDays[key], let workout = record.workouts.first else { continue }
    if let strain = StrainEngine.workoutStrain(workout: workout, daySamples: record.hrSamples, restingHR: record.restingHR, config: strainConfig) {
        check(strain > 0 && strain <= 21, "Workout-Strain (\(workout.name), \(key)) in 0–21: \(String(format: "%.1f", strain))")
        workoutStrainChecked = true
        break
    }
}
check(workoutStrainChecked, "Mindestens ein Workout-Strain berechnet")

// MARK: Alters-Engine (Pulse Alter)

section("Alters-Normen")
// Inversion trifft die Stützstellen wieder.
check(abs(AgeNorms.fitnessAge(vo2max: 48.0, sex: .male) - 25) < 1.0, "VO₂max 48 (m) → Fitness-Alter ≈ 25")
check(abs(AgeNorms.fitnessAge(vo2max: 40.3, sex: .male) - 45) < 1.0, "VO₂max 40,3 (m) → Fitness-Alter ≈ 45")
check(abs(AgeNorms.fitnessAge(vo2max: 30.9, sex: .female) - 45) < 1.0, "VO₂max 30,9 (w) → Fitness-Alter ≈ 45")
// Monotonie: fitter ⇒ jünger.
check(AgeNorms.fitnessAge(vo2max: 55, sex: .male) < AgeNorms.fitnessAge(vo2max: 35, sex: .male), "Höherer VO₂max ⇒ jüngeres Fitness-Alter")
let fitVeryHigh = AgeNorms.fitnessAge(vo2max: 65, sex: .male)
check(fitVeryHigh >= 20 && fitVeryHigh <= 25, "Sehr hoher VO₂max wird auf ≥20 geklemmt (\(String(format: "%.0f", fitVeryHigh)))")
check(abs(AgeNorms.hrvAge(rmssd: 46) - 35) < 1.5, "RMSSD 46 → HRV-Alter ≈ 35")
check(AgeNorms.hrvAge(rmssd: 60) < AgeNorms.hrvAge(rmssd: 25), "Höhere HRV ⇒ jüngeres HRV-Alter")
// Geschlecht verschiebt die Kurve.
check(AgeNorms.vo2max(age: 40, sex: .male) > AgeNorms.vo2max(age: 40, sex: .female), "VO₂max-Norm: Männer > Frauen bei gleichem Alter")

section("Alters-Engine")
let fitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [52, 51, 53, 52, 54],
    rmssdValues: Array(repeating: 57, count: 10),
    restingHRValues: Array(repeating: 51, count: 10),
    sleepPerformances: [88, 90, 87, 91],
    stepsValues: [12000, 11500, 12500],
    validDayCount: 30
)
let fitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: fitInputs)
if let pulseAge = fitResult.pulseAge, let delta = fitResult.deltaYears {
    check(pulseAge >= 15 && pulseAge <= 95, "Fitter 30-Jähriger: Pulse-Alter in Grenzen (\(String(format: "%.0f", pulseAge)))")
    check(delta < 0, "Fitter Mensch ist biologisch jünger (Δ \(String(format: "%.0f", delta)))")
    check(!fitResult.vo2maxEstimated, "Gemessener VO₂max wird bevorzugt (nicht geschätzt)")
} else {
    check(false, "Pulse-Alter trotz voller Daten nil")
}

let unfitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: Array(repeating: 30, count: 5),
    rmssdValues: Array(repeating: 25, count: 10),
    restingHRValues: Array(repeating: 72, count: 10),
    sleepPerformances: [60, 63, 58],
    stepsValues: [3000, 2800, 3200],
    validDayCount: 30
)
let unfitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: unfitInputs)
check((unfitResult.deltaYears ?? 0) > 0, "Unfitter Mensch ist biologisch älter (Δ \(String(format: "%.0f", unfitResult.deltaYears ?? 0)))")
check((fitResult.pulseAge ?? 0) < (unfitResult.pulseAge ?? 0), "Fit < Unfit im Pulse-Alter")

// Kalibrierungs-Gate: zu wenig Tage ⇒ kein Wert.
let earlyInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [50, 51, 52],
    rmssdValues: Array(repeating: 55, count: 8),
    restingHRValues: Array(repeating: 52, count: 8),
    validDayCount: 10
)
let earlyResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: earlyInputs)
check(earlyResult.pulseAge == nil, "Unter 14 gültigen Tagen: noch kein Pulse-Alter")
check(earlyResult.calibrating, "Frühe Phase ist als kalibrierend markiert")
check(earlyResult.calibrationHave == 10, "Kalibrierungsfortschritt zählt gültige Tage")

// Doppelzählungs-Schutz: ohne gemessenen VO₂max wird geschätzt UND der
// Ruhepuls fließt dann NICHT zusätzlich als Korrektur ein.
let estimatedInputs = AgeInputs(
    chronoAge: 40, sex: .male,
    vo2maxValues: [],
    rmssdValues: Array(repeating: 40, count: 10),
    restingHRValues: Array(repeating: 58, count: 12),
    observedMaxHR: 185,
    sleepPerformances: [80, 82],
    stepsValues: [9000, 8500],
    validDayCount: 30
)
let estimatedResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: estimatedInputs)
check(estimatedResult.vo2maxEstimated, "Ohne Messwert: VO₂max wird über HF-Ratio geschätzt")
check(estimatedResult.vo2max != nil, "Geschätzter VO₂max ist vorhanden")
check(!estimatedResult.components.contains { $0.key == "rhr" }, "Bei geschätztem VO₂max keine separate Ruhepuls-Korrektur (kein Doppelzählen)")
check(estimatedResult.components.contains { $0.key == "fitness" }, "Fitness-Komponente auch im Schätz-Pfad vorhanden")

// Ende-zu-Ende auf Demo-Daten (gemessener VO₂max ~50).
let ageWindow = sortedKeys.suffix(30).compactMap { demoDays[$0] }
let ageSleepPerf = sortedKeys.suffix(30).compactMap { key -> Double? in
    guard let a = sleepAnalyses[key], a.hasData else { return nil }
    return a.performance
}
let demoAgeInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: ageWindow.compactMap { $0.vo2max },
    rmssdValues: ageWindow.compactMap { $0.hrvRmssd },
    restingHRValues: ageWindow.compactMap { $0.restingHR },
    sleepPerformances: ageSleepPerf,
    stepsValues: ageWindow.compactMap { $0.steps.map(Double.init) },
    validDayCount: ageWindow.filter { $0.hrvRmssd != nil || $0.restingHR != nil }.count
)
let demoAgeResult = AgeEngine.compute(dateKey: sortedKeys.last!, inputs: demoAgeInputs)
check(demoAgeResult.vo2max != nil, "Demo: VO₂max vorhanden")
if let demoPulseAge = demoAgeResult.pulseAge {
    check(demoPulseAge >= 15 && demoPulseAge <= 45, "Demo: Pulse-Alter plausibel (\(String(format: "%.0f", demoPulseAge)))")
} else {
    check(false, "Demo: Pulse-Alter trotz 30 Tagen nil")
}

// MARK: Journal & Korrelation

section("Journal & Korrelation")
var journalEntries: [String: JournalEntry] = [:]
var journalRecovery: [String: Int] = [:]
for i in 0..<12 {
    let day = DayKey.addDays("2026-06-01", i)
    let alcohol = i % 2 == 0
    let factors: Set<JournalFactor> = alcohol ? [.alcohol] : []
    journalEntries[day] = JournalEntry(date: day, factors: factors)
    journalRecovery[DayKey.addDays("2026-06-01", i + 1)] = alcohol ? 45 : 75
}
let insights = JournalEngine.insights(entries: journalEntries, recoveryByDay: journalRecovery)
if let alc = insights.first(where: { $0.factor == .alcohol }) {
    check(alc.delta < -15, "Alkohol senkt Folge-Recovery deutlich (Δ \(Int(alc.delta)))")
    check(alc.daysWith >= 5 && alc.daysWithout >= 5, "Beide Gruppen über Whoop-Mindestfallzahl (5/5)")
    check(alc.confidence == .solid, "Klarer, konsistenter Effekt → belastbar")
} else {
    check(false, "Alkohol-Insight fehlt trotz Daten")
}
check(!insights.contains { $0.factor == .sick }, "Faktor ohne Einträge liefert kein Insight")
check(JournalFactor.allCases.contains(.sex), "Sex ist als Journal-Faktor vorhanden")

// Verrauschter Mini-Effekt → nur Tendenz, nicht belastbar.
var noisyEntries: [String: JournalEntry] = [:]
var noisyRecovery: [String: Int] = [:]
// Gruppen-Mittel fast gleich (~68), aber hohe Streuung → kein echter Effekt.
let noisyScores = [55, 58, 80, 77, 60, 63, 75, 74, 65, 70, 72, 68]
for i in 0..<12 {
    let day = DayKey.addDays("2026-05-01", i)
    noisyEntries[day] = JournalEntry(date: day, factors: i % 2 == 0 ? [.lateMeal] : [])
    noisyRecovery[DayKey.addDays("2026-05-01", i + 1)] = noisyScores[i]
}
if let noisy = JournalEngine.insights(entries: noisyEntries, recoveryByDay: noisyRecovery).first(where: { $0.factor == .lateMeal }) {
    check(noisy.confidence == .emerging, "Kleiner Effekt in starkem Rauschen → nur Tendenz (Δ \(String(format: "%.1f", noisy.delta)), SE \(String(format: "%.1f", noisy.standardError)))")
} else {
    check(false, "Rausch-Insight fehlt trotz 6/6 Tagen")
}

check(!JournalEngine.assessmentReady(recoveryByDay: journalRecovery), "Unter 28 Recovery-Tagen: Monats-Auswertung noch nicht bereit")
var manyRecoveries: [String: Int] = [:]
for i in 0..<30 { manyRecoveries[DayKey.addDays("2026-05-01", i)] = 70 }
check(JournalEngine.assessmentReady(recoveryByDay: manyRecoveries), "Ab 28 Recovery-Tagen: Monats-Auswertung bereit")

let tmpJournal = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-journal-\(UUID().uuidString)")
let jStore = JournalStore(directory: tmpJournal)
jStore.toggle(.alcohol, on: "2026-07-18")
check(jStore.isSet(.alcohol, on: "2026-07-18"), "Toggle setzt Faktor")
check(jStore.save(), "Journal speichern erfolgreich")
let jReload = JournalStore(directory: tmpJournal)
check(jReload.isSet(.alcohol, on: "2026-07-18"), "Journal übersteht Roundtrip")
try? FileManager.default.removeItem(at: tmpJournal)

// MARK: Zubettgeh-Empfehlung

section("Zubettgeh-Empfehlung")
var wakeComps = DateComponents()
wakeComps.year = 2026; wakeComps.month = 6; wakeComps.day = 10; wakeComps.hour = 6; wakeComps.minute = 45
let wake645 = Calendar.current.date(from: wakeComps)!
let bedRec = SleepEngine.bedtimeRecommendation(
    currentDebtMinutes: 0, strainToday: 3, recentWakeTimes: [wake645, wake645, wake645]
)
check(abs(bedRec.projectedNeedMinutes - 456) < 5, "Ohne Schuld/Strain ≈ Basisbedarf (\(Int(bedRec.projectedNeedMinutes)))")
if let bed = bedRec.recommendedBedtimeMinutes {
    check(abs(bed - 1389) < 3, "Zubettgehzeit = Aufwachzeit − Bedarf (\(Int(bed)/60):\(String(format: "%02d", Int(bed)%60)))")
} else {
    check(false, "Keine Bedtime trotz Aufwachzeiten")
}
let bedRecHard = SleepEngine.bedtimeRecommendation(currentDebtMinutes: 120, strainToday: 16, recentWakeTimes: [wake645])
check(bedRecHard.projectedNeedMinutes > bedRec.projectedNeedMinutes, "Schuld + harter Tag erhöhen den Bedarf")

// MARK: Health-Warnung

section("Health-Warnung")
func healthRecord(_ key: String, rhr: Double, resp: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr; r.respiratoryRate = resp; r.hrvRmssd = 60; r.spo2Avg = 97; r.bodyTemp = 34
    return r
}
var stableRecords = (0..<8).map { healthRecord(DayKey.addDays("2026-06-01", $0), rhr: 55, resp: 14) }
check(HealthMonitor.alert(records: stableRecords) == nil, "Stabile Werte → keine Warnung")
stableRecords.append(healthRecord(DayKey.addDays("2026-06-01", 8), rhr: 70, resp: 18))
if let multi = HealthMonitor.alert(records: stableRecords) {
    check(multi.kinds.count >= 2, "Mehrere auffällige Werte → Warnung mit ≥2 Metriken")
} else {
    check(false, "Warnung fehlt trotz zwei auffälliger Werte")
}
var streakRecords = (0..<7).map { healthRecord(DayKey.addDays("2026-07-01", $0), rhr: 55, resp: 14) }
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 7), rhr: 68, resp: 14))
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 8), rhr: 69, resp: 14))
if let streak = HealthMonitor.alert(records: streakRecords) {
    check(streak.kinds == [.restingHR], "Einzelne Metrik über 2 Tage → Streak-Warnung")
} else {
    check(false, "Streak-Warnung fehlt")
}

// MARK: Sync-Helfer

section("Sync-Helfer")
let base = DayKey.date(from: "2026-07-17")!
let rawSamples = (0..<120).map { i in
    SamplePoint(time: base.addingTimeInterval(Double(i) * 5), value: 60 + Double(i % 10))
}
let downsampled = SyncEngine.downsampleToMinutes(rawSamples)
check(downsampled.count == 10, "600 s in 5-s-Auflösung → 10 Minuten-Buckets")
check(downsampled.allSatisfy { $0.bpm >= 60 && $0.bpm <= 70 }, "Downsampling mittelt korrekt")

let nightSamples = [
    SamplePoint(time: DayKey.date(from: "2026-07-16")!.addingTimeInterval(23.5 * 3600), value: 55),
    SamplePoint(time: DayKey.date(from: "2026-07-17")!.addingTimeInterval(3 * 3600), value: 65),
]
let grouped = SyncEngine.groupByNight(nightSamples)
check(grouped["2026-07-17"]?.count == 2, "Nacht-Gruppierung fasst Abend + Morgen zusammen")

// Rate-Limit-Backoff (Google: 300 Requests/min/Nutzer).
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "7") == 7, "Retry-After-Header wird respektiert")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: nil) == 2, "Ohne Header: exponentiell ab 2 s")
check(HealthAPIClient.retryDelay(attempt: 2, retryAfterHeader: nil) == 8, "Exponentieller Anstieg (Versuch 3 → 8 s)")
check(HealthAPIClient.retryDelay(attempt: 9, retryAfterHeader: nil) == 60, "Backoff bei 60 s gekappt")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "120") == 60, "Retry-After bei 60 s gekappt")

// Inkrementeller HF-Sync: geprüfte Vergangenheitstage werden übersprungen.
let oldKey = DayKey.addDays(DayKey.today(), -3)
var oldFull = DayRecord(date: oldKey)
oldFull.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
oldFull.hrSyncedAt = Date() // nach Tagesende geprüft
check(SyncEngine.isIntradayComplete(oldFull, dayKey: oldKey), "Alter Tag mit Daten, nach Tagesende geprüft → übersprungen")
var oldEmpty = DayRecord(date: oldKey)
oldEmpty.hrSyncedAt = Date() // leer, aber geprüft
check(SyncEngine.isIntradayComplete(oldEmpty, dayKey: oldKey), "Alter LEERER Tag, einmal geprüft → wird NICHT erneut geladen")
let yesterdayKey = DayKey.addDays(DayKey.today(), -1)
var yest = DayRecord(date: yesterdayKey)
yest.hrSamples = [HRSample(t: DayKey.date(from: yesterdayKey)!, bpm: 60)]
yest.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(yest, dayKey: yesterdayKey), "Gestern wird immer neu geladen (verspätete Uhr-Daten)")
var todayDay = DayRecord(date: DayKey.today())
todayDay.hrSamples = [HRSample(t: Date(), bpm: 60)]
todayDay.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(todayDay, dayKey: DayKey.today()), "Heute gilt nie als vollständig")
var oldUnstamped = DayRecord(date: oldKey)
oldUnstamped.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
check(!SyncEngine.isIntradayComplete(oldUnstamped, dayKey: oldKey), "Ohne hrSyncedAt-Stempel wird geladen")
check(!SyncEngine.isIntradayComplete(nil, dayKey: oldKey), "Fehlender Tag wird geladen")

// Spike-Filter: isolierte Artefakt-Spitze wird geglättet, Rampe bleibt.
let spikeSamples = [60.0, 62, 175, 61, 63].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
let deSpiked = SyncEngine.removeSpikes(spikeSamples)
check(deSpiked[2].bpm < 100, "Isolierte HF-Spitze (175) wird geglättet → \(Int(deSpiked[2].bpm))")
let rampSamples = [60.0, 105, 150, 175].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
check(SyncEngine.removeSpikes(rampSamples).map(\.bpm) == rampSamples.map(\.bpm), "Monotoner Anstieg bleibt unangetastet")

// MARK: Store-Roundtrip

section("MetricsStore")
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("pulse-selftest-\(UUID().uuidString)")
let store = MetricsStore(directory: tempDir)
store.merge(Array(demoDays.values))
check(store.days.count == 120, "Store enthält 120 Tage")
check(store.save(), "Speichern erfolgreich")

let reloaded = MetricsStore(directory: tempDir)
check(reloaded.days.count == 120, "Reload liefert 120 Tage")
if let lastKey = sortedKeys.last {
    let original = store.days[lastKey]
    let restored = reloaded.days[lastKey]
    check(original?.hrvRmssd == restored?.hrvRmssd, "HRV übersteht Roundtrip")
    // ISO-8601-Encoding rundet Dates auf ganze Sekunden → tolerant vergleichen.
    let hrStampDelta = abs((original?.hrSyncedAt?.timeIntervalSince1970 ?? -1) - (restored?.hrSyncedAt?.timeIntervalSince1970 ?? -2))
    check(hrStampDelta < 1, "hrSyncedAt übersteht Roundtrip (Sekunden-Präzision)")
    check(original?.sleepSessions.count == restored?.sleepSessions.count, "Schlaf-Sessions überstehen Roundtrip")
    check((restored?.hrSamples.count ?? 0) > 0, "HR-Samples des letzten Tages erhalten")
}
let historyCheck = reloaded.history(before: sortedKeys.last!, days: 30)
check(historyCheck.count == 30, "history(before:) liefert 30 Tage")
try? FileManager.default.removeItem(at: tempDir)

// MARK: Ergebnis

print("")
if failures.isEmpty {
    print("ALLE TESTS BESTANDEN ✅")
    exit(0)
} else {
    print("\(failures.count) TEST(S) FEHLGESCHLAGEN ❌")
    for failure in failures {
        print("  – \(failure)")
    }
    exit(1)
}

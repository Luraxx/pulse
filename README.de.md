# Pulse — dein persönliches Whoop für die Fitbit Air

Pulse ist eine private iOS-App, die die Daten deiner **Google Fitbit Air** über die
**Google Health API** liest und daraus Whoop-artige Metriken berechnet:

- **Recovery-Score (1–99 %)** aus HRV, Ruhepuls, Schlafperformance und Atemfrequenz —
  jeweils gegen deine persönliche 30-Tage-Baseline
- **Strain (0–21)** — kardiovaskuläre Tagesbelastung aus Herzfrequenz-Reserve-Zonen,
  logarithmische Skala wie bei Whoop, inkl. Strain pro Workout
- **Schlafbedarf, Schlafschuld, Performance, Konsistenz, Effizienz** + Phasen-Hypnogramm
- **Health-Monitor**: Ruhepuls, HRV, Atemfrequenz, SpO₂ und Hauttemperatur im
  persönlichen Baseline-Band (± 1,65 SD) mit Warnstatus
- **Pulse Alter** — dein biologisches Alter aus VO₂max, HRV, Ruhepuls, Schlaf und
  Aktivität, gegen geschlechts- und altersspezifische Normwerte (kalibriert ~30 Tage)
- **Trends** über 7/30/90 Tage (Recovery vs. Strain, Schlaf, HRV, Ruhepuls)

Alle Daten bleiben **lokal auf dem iPhone** (JSON in Application Support). Kein Server,
kein Abo, kein Tracking.

---

## Wichtig: Warum Google Health API (und nicht Fitbit Web API)?

Die klassische **Fitbit Web API wird im September 2026 abgeschaltet**. Google ersetzt
sie durch die **Google Health API** (`https://health.googleapis.com/v4`) mit Google
OAuth 2.0. Die Fitbit Air synct ohnehin in die **Google Health App** — Pulse ist
deshalb direkt gegen die neue API gebaut. Quellen:

- https://developers.google.com/health/about (Überblick, Sunset-Termin)
- https://developers.google.com/health/setup (Cloud-Setup)
- https://developers.google.com/health/scopes (Scopes)
- https://developers.google.com/health/endpoints (Endpunkte)
- https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ (Fitbit Air)

Da die API neu ist (v4, Launch Mai 2026) und nicht alle Feld­namen final dokumentiert
sind, dekodiert Pulse **tolerant** (Kandidaten-Keys, Lesevarianten-Fallback) und
protokolliert jede Metrik einzeln im **Sync-Protokoll** (unter „Mehr“). Einzelne
fehlende Datentypen blockieren nie den Rest.

---

## Voraussetzungen

| Was | Status |
| --- | --- |
| iPhone mit iOS 17+ und Google-Health-App (Fitbit Air gekoppelt) | dein Gerät |
| Mac mit **Xcode 16+** | ⚠️ aktuell nicht installiert → App Store |
| `xcodegen` (`brew install xcodegen`) | ✅ installiert |
| Google-Konto (dasselbe wie in der Google-Health-App) | dein Konto |

---

## Teil 1: Google Cloud einrichten (einmalig, ~10 Minuten)

1. **Projekt anlegen:** [console.cloud.google.com](https://console.cloud.google.com)
   → neues Projekt, z. B. `pulse-personal`.
2. **API aktivieren:** [API-Bibliothek](https://console.developers.google.com/apis/library/health.googleapis.com)
   → **Google Health API** → *Aktivieren*.
3. **OAuth-Zustimmungsbildschirm** (Google Auth Platform → Branding/Audience):
   - User Type: **External**, Publishing-Status: **Testing**
   - Unter **Audience → Test users**: deine eigene Google-Adresse hinzufügen.
4. **Scopes freigeben** (Google Auth Platform → **Data Access** →
   „Add or remove scopes“ → nach „Google Health API“ suchen) — diese vier Read-Scopes:
   - `…/auth/googlehealth.health_metrics_and_measurements.readonly`
   - `…/auth/googlehealth.sleep.readonly`
   - `…/auth/googlehealth.activity_and_fitness.readonly`
   - `…/auth/googlehealth.profile.readonly`
5. **iOS-Client-ID erstellen:** APIs & Services → **Credentials** →
   *Create Credentials* → *OAuth client ID* → Application type **iOS** →
   Bundle ID: **`net.dehlwes.pulse`** → die erzeugte Client-ID kopieren
   (Form: `1234567890-abc….apps.googleusercontent.com`).
   Es wird **kein Client-Secret** benötigt (PKCE).

> ⏳ **Testing-Modus-Hinweis:** Solange das Projekt auf „Testing“ steht, laufen
> Refresh-Tokens nach **7 Tagen** ab. Pulse zeigt das als „Neu verbinden“-Hinweis —
> ein Tap, fertig. (Eine Veröffentlichung würde bei den restricted Health-Scopes eine
> Google-Prüfung erfordern — für den Privatgebrauch unnötig.)

---

## Teil 2: App bauen & aufs iPhone bringen

```bash
open Pulse.xcodeproj
```

> ⚠️ Wichtig: **`Pulse.xcodeproj` öffnen** — nicht den Ordner oder `Package.swift`!
> Öffnet man den Ordner, zeigt Xcode nur die SwiftPM-Schemes (`PulseCore`,
> `pulse-selftest`); das sind macOS-Testziele und lassen sich nicht auf einem
> iPhone installieren. Oben in der Toolbar muss das Scheme **Pulse** gewählt sein.
> Das Projekt liegt fertig im Repo; nur nach Änderungen an `project.yml` muss es
> mit `xcodegen generate` neu erzeugt werden.

In Xcode: Target **Pulse** → *Signing & Capabilities* → dein persönliches Team wählen
(kostenlose Apple-ID reicht) → iPhone anschließen → ▶︎ Run.

**In der App:** „Mit Google Health verbinden“ → Client-ID einfügen → Google-Login im
System-Browser → fertig. Der erste Sync lädt 60 Tage Historie (einstellbar), danach
genügt Pull-to-Refresh. Ohne Google-Setup kannst du sofort den **Demo-Modus** starten
(120 Tage realistische Beispieldaten).

---

## Projektstruktur

```
pulse/
├── Pulse.xcodeproj      # fertig generiert – hier reinschauen zum Bauen
├── project.yml          # xcodegen-Definition (nur bei Änderungen neu generieren)
├── App/                 # iOS-spezifisch: SwiftUI, OAuth-Browser-Flow, Assets
│   ├── PulseApp.swift / AppModel.swift (zentrales @Observable-Modell)
│   ├── Auth/WebAuthenticator.swift    (ASWebAuthenticationSession)
│   └── UI/              # Dashboard, Recovery/Schlaf/Strain-Detail, Trends,
│                        # Gesundheit, Einstellungen, Onboarding, Charts, Theme
├── Core/                # plattformneutral, ohne UIKit/SwiftUI
│   ├── Models/          # DayRecord, SleepSession, Workout, MetricsStore (JSON)
│   ├── Metrics/         # RecoveryEngine, StrainEngine, SleepEngine, HealthMonitor
│   ├── API/             # GoogleAuth (PKCE, Keychain), HealthAPIClient, JSONExtract
│   ├── Sync/SyncEngine.swift
│   ├── Demo/DemoData.swift
│   └── Package.swift     # macht Core als Bibliothek für die Self-Tests nutzbar
└── SelfTest/            # eigenes SwiftPM-Paket, getrennt vom App-Projekt
    └── Sources/pulse-selftest/main.swift
```

**Self-Tests ohne Xcode ausführen** (prüft PKCE gegen den RFC-7636-Vektor,
DTO-Dekodierung mit Google-Health-Fixtures, alle Metrik-Engines Ende-zu-Ende auf
Demo-Daten, Store-Roundtrip):

```bash
cd SelfTest && swift run pulse-selftest
```

> Die Self-Tests liegen bewusst in einem **eigenen Unterpaket**. Dadurch gibt es
> im Projekt-Wurzelverzeichnis keine `Package.swift` mehr – Xcode kann den Ordner
> also nicht versehentlich als Swift-Package öffnen, und der Play-Button baut immer
> die richtige App statt des Test-Runners.

---

## Wie die Scores gerechnet werden

### Recovery (1–99 %)
| Komponente | Gewicht | Methode |
| --- | --- | --- |
| HRV (nächtl. RMSSD) | 40 % | ln-transformiert, z-Score vs. 30-Tage-Baseline → Logistik |
| Ruhepuls | 25 % | z-Score invertiert → Logistik |
| Schlaf | 25 % | Schlafperformance des Vorabends |
| Atemfrequenz | 10 % | Abzug nur bei Erhöhung über Baseline |

Abzüge: SpO₂-Minimum < 90 % (−7), Temperatur > +1,8 SD (−5).
Zonen wie Whoop: **≥ 67 grün**, 34–66 gelb, < 34 rot. Fehlende Komponenten werden
umgewichtet; unter 5 Nächten Baseline zeigt die App „kalibriert noch“.

### Strain (0–21)
Zeit in Zonen der **Herzfrequenz-Reserve** (Karvonen; MaxHF = Tanaka `208 − 0,7·Alter`
oder manuell) wird gewichtet summiert (Zonen ab 20 % HRR, Gewichte 0,5→11) und
logarithmisch abgebildet: `Strain = 21 · (1 − e^(−Load/450))`.
Kalibrierung: lockerer Tag ≈ 2–4, solides Training ≈ 10, harter Tag ≈ 18.
Ohne Intraday-HF greift ein Fallback über Workout-Durchschnittspuls + Schritte.

### Schlaf
`Bedarf = Basis (Standard 7:36 h, einstellbar) + 30 % der Schlafschuld + bis zu
45 min Strain-Aufschlag (ab Strain 8 des Vortags)`.
Schuld akkumuliert bei Unterschreitung (Kappung 5 h), Überschlafen baut ab.
Konsistenz = Abweichung der Zubettgeh-/Aufwachzeiten vs. letzte 4 Nächte.

### Pulse Alter (biologisches Alter)

Der Score schätzt, wie „alt" dein Körper physiologisch wirkt — er kann unter oder
über deinem echten Alter liegen. Aufbau ([AgeEngine.swift](Core/Metrics/AgeEngine.swift)):

1. **Rückgrat: VO₂max → Fitness-Alter.** VO₂max ist der stärkste Einzelprädiktor
   der Gesamtmortalität (Mandsager, *JAMA Netw Open* 2018, 122 007 Personen; jede
   1-MET-Steigerung ≈ 13–15 % geringeres Sterberisiko). Pulse nutzt bevorzugt den
   von Google Health **gemessenen** VO₂max (`daily-vo2-max`). Fehlt er, wird er über
   die **Herzfrequenz-Ratio-Methode** geschätzt (Uth et al. 2004:
   `VO₂max ≈ 15,3 × HRmax/HRruhe`, HRmax aus real beobachtetem Maxpuls oder
   Nes/HUNT `211 − 0,64 × Alter`). Der Messwert wird über die **FRIEND**-Normwerte
   (50. Perzentil, geschlechtsspezifisch; Kaminsky, *Mayo Clin Proc* 2015) in ein
   Alter übersetzt.
2. **HRV → HRV-Alter.** Nächtlicher RMSSD gegen alterstypische Referenzwerte.
3. Beide Äquivalenzalter werden gewichtet gemittelt (**VO₂max 0,7 / HRV 0,3**).
4. **Gedeckelte Korrekturen** aus Ruhepuls (+10 S/min ≈ HR 1,09 Mortalität, Zhang
   *CMAJ* 2016), Schlafperformance und Aktivität (zusammen max. ± 5 Jahre).

Gegen Doppelzählung: Der Ruhepuls-Zuschlag entfällt, wenn VO₂max **geschätzt**
wurde — dann steckt der Ruhepuls schon im Rückgrat. Der Score erscheint erst nach
**~30 Tagen** mit Messwerten (provisorisch ab 14), vorher „kalibriert noch". Alter
und Geschlecht (Einstellung unter „Mehr") bestimmen die Normkurven. **Orientierung,
kein medizinischer Befund.**

Quellen: [Mandsager 2018](https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2707428) ·
[FRIEND/Kaminsky 2015](https://pmc.ncbi.nlm.nih.gov/articles/PMC4919021/) ·
[Uth 2004](https://pubmed.ncbi.nlm.nih.gov/14624296/) ·
[Zhang 2016](https://www.cmaj.ca/content/188/3/E53)

---

## Datentypen-Mapping (Google Health API v4)

| Metrik | dataType (URL) | Payload-Key | Anmerkung |
| --- | --- | --- | --- |
| Herzfrequenz intraday | `heart-rate` | `heartRate` | ~5-s-Auflösung, App reduziert auf 1 min |
| HRV | `heart-rate-variability` | `heartRateVariability` | nächtl. Mittel aus Samples; Fallback `daily-heart-rate-variability` |
| Schlaf | `sleep` | `sleep` | Sessions mit `stages[]` + `summary`, Zeit in `interval` |
| Atemfrequenz | `daily-respiratory-rate` | `dailyRespiratoryRate` | Tageswert (`date`-Filter), `breathsPerMinute` |
| SpO₂ | `oxygen-saturation` | `oxygenSaturation` | Ø + Minimum je Nacht |
| Temperatur | `daily-sleep-temperature-derivations` | `dailySleepTemperatureDerivations` | nächtl. Hauttemperatur (`nightlyTemperatureCelsius`) |
| Ruhepuls | `daily-resting-heart-rate` | `dailyRestingHeartRate` | Tageswert; Fallback: 5. Perzentil der Nacht-HF |
| VO₂max | `daily-vo2-max` | `dailyVo2Max` | Cardio-Fitness (ml/kg/min); Fallback: HF-Ratio-Schätzung |
| Schritte | `steps` | `steps` | Intervall-Samples → Tagessumme |
| Workouts | `exercise` | `exercise` | Filter über `interval.civil_start_time` (Zivilzeit, ohne Z); Ø-Puls/Kalorien |

Der Client probiert je Typ automatisch `…:reconcile` → `list` (Bereichsfilter) →
`list` (nur Startfilter) und merkt sich die funktionierende Variante. Sollte Google
einen Typ anders benennen, siehst du es im **Sync-Protokoll** und passt nur die
Strings in [SyncEngine.swift](Core/Sync/SyncEngine.swift) an.

---

## Troubleshooting

- **„Anmeldung abgelaufen … neu verbinden“** → normal im Testing-Modus (7 Tage),
  einfach neu verbinden.
- **HTTP 403 beim Sync** → Google Health API im Cloud-Projekt nicht aktiviert oder
  Scope auf der Data-Access-Seite nicht hinzugefügt.
- **`access_denied` beim Login** → deine Adresse fehlt unter *Audience → Test users*.
- **Einzelne Metriken leer** → Sync-Protokoll prüfen; Datentyp evtl. für die Fitbit
  Air (noch) nicht befüllt oder anders benannt (Mapping-Tabelle oben anpassen).
- **Widget baut nicht / Signing-Fehler** → Das Widget (`PulseWidget`) nutzt eine
  **App Group** (`group.net.dehlwes.pulse`), um den Recovery-Score mit der App zu
  teilen. Xcode verwaltet das bei automatischem Signing selbst; bei einer
  **kostenlosen Apple-ID** kann es sein, dass du in *Signing & Capabilities* für
  **beide** Targets (Pulse + PulseWidget) einmal dein Team wählen und die App-Group
  bestätigen musst. Zickt es weiterhin, kannst du das Widget mit `git revert` des
  Widget-Commits entfernen – der Rest der App bleibt unberührt.
- **Hintergrund-Sync läuft nicht sekundengenau** → normal. iOS führt
  `BGAppRefreshTask` opportunistisch aus (meist nachts/morgens), nicht auf Zuruf.

## Roadmap-Ideen

- Live-„Stress-Monitor“ aus Tages-HRV/HF-Abweichung
- Verhaltens-Journal mit Korrelationen (à la Whoop Journal)
- Home-Screen-Widget + Watch-Komplikation
- Webhook-Subscriptions statt Polling (`v4/projects/*/subscribers`)
- Export (CSV/Health Connect)

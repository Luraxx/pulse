import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnectSheet = false
    @State private var confirmReset = false
    @State private var confirmDemoEnd = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                languageSection
                connectionSection
                syncSection
                notificationsSection
                ProfileFields(model: model)
                calculationSection(model: $model)
                demoSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(model.loc("Mehr", "More"))
            .sheet(isPresented: $showConnectSheet) {
                ConnectSheet()
            }
        }
    }

    // MARK: - Sprache

    private var languageSection: some View {
        @Bindable var model = model
        return Section {
            Picker(model.loc("Sprache", "Language"), selection: $model.language) {
                ForEach(PulseLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
        } header: {
            Text(model.loc("Sprache", "Language"))
        }
    }

    // MARK: - Verbindung

    private var connectionSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isConnected ? Theme.green : Theme.textSecondary)
                        .frame(width: 8, height: 8)
                    Text(model.isConnected ? model.loc("Verbunden", "Connected") : model.loc("Nicht verbunden", "Not connected"))
                }
            }
            if let name = model.profileName {
                LabeledContent(model.loc("Konto", "Account"), value: name)
            }
            Button(model.isConnected ? model.loc("Neu verbinden", "Reconnect") : model.loc("Mit Google Health verbinden", "Connect Google Health")) {
                showConnectSheet = true
            }
            if model.isConnected {
                Button(model.loc("Verbindung trennen", "Disconnect"), role: .destructive) {
                    model.disconnect()
                }
            }
        } header: {
            Text("Google Health")
        } footer: {
            Text(model.loc("Hinweis: Solange dein Google-Cloud-Projekt im Status „Testing“ ist, läuft die Anmeldung alle 7 Tage ab und muss per „Neu verbinden“ erneuert werden.", "Note: while your Google Cloud project is in Testing status, the sign-in expires every 7 days and must be renewed via Reconnect."))
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        @Bindable var model = model
        return Section(model.loc("Synchronisierung", "Sync")) {
            Button {
                Task { await model.syncNow() }
            } label: {
                HStack {
                    Text(model.syncing ? model.syncMessage : model.loc("Jetzt synchronisieren", "Sync now"))
                    Spacer()
                    if model.syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(!model.isConnected || model.syncing)

            if let lastSync = model.lastSyncAt {
                LabeledContent(model.loc("Letzter Sync", "Last sync"), value: Fmt.relative(lastSync))
            }

            Picker(model.loc("Zeitraum (Backfill)", "Range (backfill)"), selection: $model.daysBack) {
                Text(model.loc("30 Tage", "30 days")).tag(30)
                Text(model.loc("60 Tage", "60 days")).tag(60)
                Text(model.loc("90 Tage", "90 days")).tag(90)
                Text(model.loc("180 Tage", "180 days")).tag(180)
            }
            Picker(model.loc("Intraday-Herzfrequenz", "Intraday heart rate"), selection: $model.hrDaysBack) {
                Text(model.loc("7 Tage", "7 days")).tag(7)
                Text(model.loc("14 Tage", "14 days")).tag(14)
                Text(model.loc("28 Tage", "28 days")).tag(28)
            }

            NavigationLink(model.loc("Sync-Protokoll", "Sync log")) {
                SyncLogView()
            }
        }
    }

    // MARK: - Benachrichtigungen

    private var notificationsSection: some View {
        Section {
            Toggle(model.loc("Morgendliche Recovery-Meldung", "Morning recovery notification"), isOn: Binding(
                get: { model.notificationsEnabled },
                set: { on in Task { await model.setNotifications(enabled: on) } }
            ))
        } header: {
            Text(model.loc("Benachrichtigungen", "Notifications"))
        } footer: {
            Text(model.loc("Morgens: deine Recovery nach dem Hintergrund-Sync – oder um 7:30 die Bitte, kurz zu öffnen, falls iOS den Sync noch nicht ausgeführt hat. Abends: Erinnerung ~30 min vor deiner empfohlenen Zubettgehzeit. Dazu Gesundheits-Warnungen in der Morgen-Meldung und eine Warnung, bevor die Google-Verbindung (7 Tage) abläuft. Alles rein lokal, nichts wird geraten – Zahlen kommen nur aus echten Syncs.", "Mornings: your recovery after the background sync – or a 7:30 reminder to open the app briefly if iOS has not run the sync yet. Evenings: a reminder ~30 min before your recommended bedtime. Plus health warnings in the morning message and an alert before the Google connection (7 days) expires. All local, nothing is guessed – numbers only come from real syncs."))
        }
    }

    // MARK: - Berechnung

    private func calculationSection(model: Bindable<AppModel>) -> some View {
        Section {
            Stepper(value: model.baseSleepNeedMinutes, in: 360...600, step: 15) {
                LabeledContent(self.model.loc("Basis-Schlafbedarf", "Base sleep need"), value: "\(Fmt.hm(model.wrappedValue.baseSleepNeedMinutes)) h")
            }
            if model.wrappedValue.maxHROverride > 0 {
                Stepper(value: model.maxHROverride, in: 130...220, step: 1) {
                    LabeledContent(self.model.loc("Max. Herzfrequenz", "Max heart rate"), value: "\(Int(model.wrappedValue.maxHROverride))")
                }
                Button(self.model.loc("Max. HF automatisch bestimmen", "Determine max HR automatically")) {
                    model.wrappedValue.maxHROverride = 0
                }
            } else {
                LabeledContent(self.model.loc("Max. Herzfrequenz", "Max heart rate"), value: "\(Int(model.wrappedValue.strainConfig.maxHR)) \(self.model.loc("(automatisch)", "(automatic)"))")
                Button(self.model.loc("Max. HF manuell festlegen", "Set max HR manually")) {
                    model.wrappedValue.maxHROverride = model.wrappedValue.strainConfig.maxHR.rounded()
                }
            }
        } header: {
            Text(self.model.loc("Berechnung", "Calculation"))
        } footer: {
            Text(self.model.loc("Max. HF automatisch = Tanaka-Formel (208 − 0,7 × Alter). Alter und Geschlecht bestimmen zudem die Normkurven fürs Pulse Alter. Alle Scores werden bei Änderungen sofort neu berechnet.", "Automatic max HR = Tanaka formula (208 − 0.7 × age). Age and sex also determine the Pulse Age reference curves. All scores are recalculated immediately on changes."))
        }
    }

    // MARK: - Demo

    private var demoSection: some View {
        Section(model.loc("Demo-Modus", "Demo mode")) {
            if model.demoMode {
                LabeledContent("Status", value: model.loc("Aktiv (generierte Daten)", "Active (generated data)"))
                Button(model.loc("Demo beenden & Daten löschen", "End demo & delete data"), role: .destructive) {
                    confirmDemoEnd = true
                }
                .confirmationDialog(model.loc("Demo-Daten wirklich löschen?", "Really delete demo data?"), isPresented: $confirmDemoEnd, titleVisibility: .visible) {
                    Button(model.loc("Löschen", "Delete"), role: .destructive) {
                        model.resetAll()
                    }
                    Button(model.loc("Abbrechen", "Cancel"), role: .cancel) {}
                }
            } else {
                Button(model.loc("Demo-Daten laden", "Load demo data")) {
                    model.startDemo()
                }
                .disabled(model.isConnected)
            }
        }
    }

    // MARK: - Daten

    private var dataSection: some View {
        Section {
            Button(model.loc("Alle Daten löschen", "Delete all data"), role: .destructive) {
                confirmReset = true
            }
            .confirmationDialog(
                model.loc("Alle lokalen Daten und die Google-Verbindung löschen?", "Delete all local data and the Google connection?"),
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button(model.loc("Alles löschen", "Delete everything"), role: .destructive) {
                    model.disconnect()
                    model.resetAll()
                }
                Button(model.loc("Abbrechen", "Cancel"), role: .cancel) {}
            }
        } footer: {
            Text(model.loc("Alle Daten liegen ausschließlich lokal auf diesem iPhone (JSON in Application Support). Es gibt keinen Server.", "All data lives exclusively on this iPhone (JSON in Application Support). There is no server."))
        }
    }

    // MARK: - Über

    private var aboutSection: some View {
        Section(model.loc("Über", "About")) {
            LabeledContent("App", value: "Pulse 1.0")
            LabeledContent(model.loc("Datenquelle", "Data source"), value: "Google Health API (v4)")
            Text(model.loc("Pulse liest die Daten deiner Fitbit Air über die Google Health API (Nachfolger der Fitbit Web API, die im September 2026 abgeschaltet wird) und berechnet daraus Whoop-artige Recovery-, Strain- und Schlaf-Scores – rein lokal, ohne Abo.", "Pulse reads your Fitbit Air data via the Google Health API (successor of the Fitbit Web API, shutting down September 2026) and computes Whoop-style recovery, strain and sleep scores – fully local, no subscription."))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Sync-Protokoll

struct SyncLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.syncLog.isEmpty {
                Text(model.loc("Noch kein Sync in dieser Sitzung.", "No sync in this session yet."))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.syncLog) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(entry.isError ? Theme.yellow : Theme.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.metric)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(model.loc("Sync-Protokoll", "Sync log"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

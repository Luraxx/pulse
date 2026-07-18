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
                connectionSection
                syncSection
                ProfileFields(model: model)
                calculationSection(model: $model)
                demoSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Mehr")
            .sheet(isPresented: $showConnectSheet) {
                ConnectSheet()
            }
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
                    Text(model.isConnected ? "Verbunden" : "Nicht verbunden")
                }
            }
            if let name = model.profileName {
                LabeledContent("Konto", value: name)
            }
            Button(model.isConnected ? "Neu verbinden" : "Mit Google Health verbinden") {
                showConnectSheet = true
            }
            if model.isConnected {
                Button("Verbindung trennen", role: .destructive) {
                    model.disconnect()
                }
            }
        } header: {
            Text("Google Health")
        } footer: {
            Text("Hinweis: Solange dein Google-Cloud-Projekt im Status „Testing“ ist, läuft die Anmeldung alle 7 Tage ab und muss per „Neu verbinden“ erneuert werden.")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        @Bindable var model = model
        return Section("Synchronisierung") {
            Button {
                Task { await model.syncNow() }
            } label: {
                HStack {
                    Text(model.syncing ? model.syncMessage : "Jetzt synchronisieren")
                    Spacer()
                    if model.syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(!model.isConnected || model.syncing)

            if let lastSync = model.lastSyncAt {
                LabeledContent("Letzter Sync", value: Fmt.relative(lastSync))
            }

            Picker("Zeitraum (Backfill)", selection: $model.daysBack) {
                Text("30 Tage").tag(30)
                Text("60 Tage").tag(60)
                Text("90 Tage").tag(90)
                Text("180 Tage").tag(180)
            }
            Picker("Intraday-Herzfrequenz", selection: $model.hrDaysBack) {
                Text("7 Tage").tag(7)
                Text("14 Tage").tag(14)
                Text("28 Tage").tag(28)
            }

            NavigationLink("Sync-Protokoll") {
                SyncLogView()
            }
        }
    }

    // MARK: - Berechnung

    private func calculationSection(model: Bindable<AppModel>) -> some View {
        Section {
            Stepper(value: model.baseSleepNeedMinutes, in: 360...600, step: 15) {
                LabeledContent("Basis-Schlafbedarf", value: "\(Fmt.hm(model.wrappedValue.baseSleepNeedMinutes)) h")
            }
            if model.wrappedValue.maxHROverride > 0 {
                Stepper(value: model.maxHROverride, in: 130...220, step: 1) {
                    LabeledContent("Max. Herzfrequenz", value: "\(Int(model.wrappedValue.maxHROverride))")
                }
                Button("Max. HF automatisch bestimmen") {
                    model.wrappedValue.maxHROverride = 0
                }
            } else {
                LabeledContent("Max. Herzfrequenz", value: "\(Int(model.wrappedValue.strainConfig.maxHR)) (automatisch)")
                Button("Max. HF manuell festlegen") {
                    model.wrappedValue.maxHROverride = model.wrappedValue.strainConfig.maxHR.rounded()
                }
            }
        } header: {
            Text("Berechnung")
        } footer: {
            Text("Max. HF automatisch = Tanaka-Formel (208 − 0,7 × Alter). Alter und Geschlecht bestimmen zudem die Normkurven fürs Pulse Alter. Alle Scores werden bei Änderungen sofort neu berechnet.")
        }
    }

    // MARK: - Demo

    private var demoSection: some View {
        Section("Demo-Modus") {
            if model.demoMode {
                LabeledContent("Status", value: "Aktiv (generierte Daten)")
                Button("Demo beenden & Daten löschen", role: .destructive) {
                    confirmDemoEnd = true
                }
                .confirmationDialog("Demo-Daten wirklich löschen?", isPresented: $confirmDemoEnd, titleVisibility: .visible) {
                    Button("Löschen", role: .destructive) {
                        model.resetAll()
                    }
                    Button("Abbrechen", role: .cancel) {}
                }
            } else {
                Button("Demo-Daten laden") {
                    model.startDemo()
                }
                .disabled(model.isConnected)
            }
        }
    }

    // MARK: - Daten

    private var dataSection: some View {
        Section {
            Button("Alle Daten löschen", role: .destructive) {
                confirmReset = true
            }
            .confirmationDialog(
                "Alle lokalen Daten und die Google-Verbindung löschen?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Alles löschen", role: .destructive) {
                    model.disconnect()
                    model.resetAll()
                }
                Button("Abbrechen", role: .cancel) {}
            }
        } footer: {
            Text("Alle Daten liegen ausschließlich lokal auf diesem iPhone (JSON in Application Support). Es gibt keinen Server.")
        }
    }

    // MARK: - Über

    private var aboutSection: some View {
        Section("Über") {
            LabeledContent("App", value: "Pulse 1.0")
            LabeledContent("Datenquelle", value: "Google Health API (v4)")
            Text("Pulse liest die Daten deiner Fitbit Air über die Google Health API (Nachfolger der Fitbit Web API, die im September 2026 abgeschaltet wird) und berechnet daraus Whoop-artige Recovery-, Strain- und Schlaf-Scores – rein lokal, ohne Abo.")
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
                Text("Noch kein Sync in dieser Sitzung.")
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
        .navigationTitle("Sync-Protokoll")
        .navigationBarTitleDisplayMode(.inline)
    }
}

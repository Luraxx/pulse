import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnectSheet = false
    @State private var step = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if step == 0 {
                welcomePage
            } else {
                ProfileSetupView(
                    onConnect: { showConnectSheet = true },
                    onDemo: { model.startDemo() },
                    onBack: { step = 0 }
                )
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSheet()
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.teal.opacity(0.25), Theme.sleepPurple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 130, height: 130)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.teal)
            }
            .padding(.bottom, 24)

            Text("Pulse")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            // Sprachwahl direkt beim Einrichten (auch später unter Mehr änderbar).
            Picker("Sprache / Language", selection: Binding(
                get: { model.language },
                set: { model.language = $0 }
            )) {
                ForEach(PulseLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .padding(.top, 10)
            Text(model.loc("Dein persönliches Recovery-System\nfür die Fitbit Air", "Your personal recovery system\nfor the Fitbit Air"))
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "arrow.clockwise.heart.fill", color: Theme.green,
                           title: model.loc("Recovery & Pulse Alter", "Recovery & Pulse Age"),
                           text: model.loc("HRV, Ruhepuls, Schlaf und VO₂max gegen deine persönliche Baseline.", "HRV, resting HR, sleep and VO₂max against your personal baseline."))
                featureRow(icon: "flame.fill", color: Theme.strainBlue,
                           title: model.loc("Strain 0–21", "Strain 0–21"),
                           text: model.loc("Kardiovaskuläre Belastung aus deinen Herzfrequenz-Zonen, wie bei Whoop.", "Cardiovascular load from your heart-rate zones, Whoop-style."))
                featureRow(icon: "bed.double.fill", color: Theme.sleepPurple,
                           title: model.loc("Schlafbedarf & -schuld", "Sleep need & debt"),
                           text: model.loc("Wie viel Schlaf du heute wirklich brauchst – inklusive Phasen-Analyse.", "How much sleep you really need tonight – including stage analysis."))
            }
            .padding(24)

            Spacer()

            Button {
                step = 1
            } label: {
                Text(model.loc("Los geht's", "Let's go"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.teal))
                    .foregroundStyle(Color.black)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func featureRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Schritt 2 des Onboardings: Profil (Alter, Geschlecht, Größe, Gewicht),
/// danach Verbindung oder Demo. Dieselben Felder liegen auch unter „Mehr".
struct ProfileSetupView: View {
    @Environment(AppModel.self) private var model
    var onConnect: () -> Void
    var onDemo: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                    Text(model.loc("Zurück", "Back"))
                }
                .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Text(model.loc("Dein Profil", "Your profile"))
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Form {
                ProfileFields(model: model)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)

            VStack(spacing: 12) {
                Button {
                    onConnect()
                } label: {
                    Text(model.loc("Mit Google Health verbinden", "Connect Google Health"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.teal))
                        .foregroundStyle(Color.black)
                }
                Button {
                    onDemo()
                } label: {
                    Text(model.loc("Erstmal mit Demo-Daten starten", "Start with demo data first"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// Wiederverwendbare Profil-Felder (Onboarding + Einstellungen).
struct ProfileFields: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Stepper(value: $model.age, in: 14...90) {
                LabeledContent(model.loc("Alter", "Age"), value: "\(model.age)")
            }
            Picker(model.loc("Geschlecht", "Sex"), selection: $model.sex) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    Text(sex.label(model.language)).tag(sex)
                }
            }
            HStack {
                Text(model.loc("Größe", "Height"))
                Spacer()
                TextField("cm", value: $model.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("cm").foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text(model.loc("Gewicht", "Weight"))
                Spacer()
                TextField("kg", value: $model.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("kg").foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text(model.loc("Körperdaten", "Body data"))
        } footer: {
            Text(model.loc("Alter und Geschlecht bestimmen die Normkurven fürs Pulse Alter und die max. Herzfrequenz. Größe und Gewicht werden fürs Profil gespeichert (VO₂max ist bereits pro kg normalisiert und ändert sich dadurch nicht).", "Age and sex determine the reference curves for Pulse Age and max heart rate. Height and weight are stored for your profile (VO₂max is already normalized per kg)."))
        }
    }
}

/// Verbindungs-Sheet: Client-ID eingeben + OAuth-Flow starten.
struct ConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField(model.loc("z. B. 1234567890-abc.apps.googleusercontent.com", "e.g. 1234567890-abc.apps.googleusercontent.com"), text: $model.clientID, axis: .vertical)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(model.loc("iOS-Client-ID (Google Cloud)", "iOS client ID (Google Cloud)"))
                } footer: {
                    Text(model.loc("Einmalig nötig: In der Google Cloud Console die **Google Health API** aktivieren, einen OAuth-Client vom Typ **iOS** anlegen und die Client-ID hier einfügen. Schritt-für-Schritt-Anleitung in der README des Projekts.", "One-time setup: enable the **Google Health API** in the Google Cloud Console, create an **iOS** OAuth client and paste the client ID here. Step-by-step guide in the project README."))
                }

                Section {
                    Button {
                        working = true
                        Task {
                            await model.connect()
                            working = false
                            if model.isConnected {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if working {
                                ProgressView().padding(.trailing, 6)
                            }
                            Text(working ? model.loc("Verbinde…", "Connecting…") : model.loc("Bei Google anmelden", "Sign in with Google"))
                        }
                    }
                    .disabled(working || !model.oauthConfig.isValid)
                } footer: {
                    if !model.clientID.isEmpty && !model.oauthConfig.isValid {
                        Text(model.loc("Die Client-ID muss auf .apps.googleusercontent.com enden.", "The client ID must end in .apps.googleusercontent.com."))
                            .foregroundStyle(Theme.red)
                    }
                }

                if let error = model.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle("Google Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.loc("Abbrechen", "Cancel")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

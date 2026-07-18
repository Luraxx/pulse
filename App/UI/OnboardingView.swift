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
            Text("Dein persönliches Recovery-System\nfür die Fitbit Air")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "arrow.clockwise.heart.fill", color: Theme.green,
                           title: "Recovery & Pulse Alter",
                           text: "HRV, Ruhepuls, Schlaf und VO₂max gegen deine persönliche Baseline.")
                featureRow(icon: "flame.fill", color: Theme.strainBlue,
                           title: "Strain 0–21",
                           text: "Kardiovaskuläre Belastung aus deinen Herzfrequenz-Zonen, wie bei Whoop.")
                featureRow(icon: "bed.double.fill", color: Theme.sleepPurple,
                           title: "Schlafbedarf & -schuld",
                           text: "Wie viel Schlaf du heute wirklich brauchst – inklusive Phasen-Analyse.")
            }
            .padding(24)

            Spacer()

            Button {
                step = 1
            } label: {
                Text("Los geht's")
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
                    Text("Zurück")
                }
                .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Text("Dein Profil")
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
                    Text("Mit Google Health verbinden")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.teal))
                        .foregroundStyle(Color.black)
                }
                Button {
                    onDemo()
                } label: {
                    Text("Erstmal mit Demo-Daten starten")
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
                LabeledContent("Alter", value: "\(model.age)")
            }
            Picker("Geschlecht", selection: $model.sex) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    Text(sex.label).tag(sex)
                }
            }
            HStack {
                Text("Größe")
                Spacer()
                TextField("cm", value: $model.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("cm").foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text("Gewicht")
                Spacer()
                TextField("kg", value: $model.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("kg").foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Körperdaten")
        } footer: {
            Text("Alter und Geschlecht bestimmen die Normkurven fürs Pulse Alter und die max. Herzfrequenz. Größe und Gewicht werden fürs Profil gespeichert (VO₂max ist bereits pro kg normalisiert und ändert sich dadurch nicht).")
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
                    TextField("z. B. 1234567890-abc.apps.googleusercontent.com", text: $model.clientID, axis: .vertical)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("iOS-Client-ID (Google Cloud)")
                } footer: {
                    Text("Einmalig nötig: In der Google Cloud Console die **Google Health API** aktivieren, einen OAuth-Client vom Typ **iOS** anlegen und die Client-ID hier einfügen. Schritt-für-Schritt-Anleitung in der README des Projekts.")
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
                            Text(working ? "Verbinde…" : "Bei Google anmelden")
                        }
                    }
                    .disabled(working || !model.oauthConfig.isValid)
                } footer: {
                    if !model.clientID.isEmpty && !model.oauthConfig.isValid {
                        Text("Die Client-ID muss auf .apps.googleusercontent.com enden.")
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
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

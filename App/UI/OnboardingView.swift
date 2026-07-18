import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnectSheet = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
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
                               title: "Recovery-Score",
                               text: "HRV, Ruhepuls, Schlaf und Atemfrequenz gegen deine persönliche Baseline.")
                    featureRow(icon: "flame.fill", color: Theme.strainBlue,
                               title: "Strain 0–21",
                               text: "Kardiovaskuläre Belastung aus deinen Herzfrequenz-Zonen, wie bei Whoop.")
                    featureRow(icon: "bed.double.fill", color: Theme.sleepPurple,
                               title: "Schlafbedarf & -schuld",
                               text: "Wie viel Schlaf du heute wirklich brauchst – inklusive Phasen-Analyse.")
                }
                .padding(24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showConnectSheet = true
                    } label: {
                        Text("Mit Google Health verbinden")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.teal))
                            .foregroundStyle(Color.black)
                    }
                    Button {
                        model.startDemo()
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
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSheet()
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

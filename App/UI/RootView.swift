import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
        .sheet(isPresented: Binding(
            get: { model.journalPromptDay != nil },
            set: { if !$0 { model.journalPromptDay = nil } }
        )) {
            if let dayKey = model.journalPromptDay {
                JournalPromptSheet(dayKey: dayKey)
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Heute", systemImage: "gauge.with.needle") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            HealthMonitorView()
                .tabItem { Label("Gesundheit", systemImage: "heart.text.square.fill") }
            SettingsView()
                .tabItem { Label("Mehr", systemImage: "gearshape.fill") }
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

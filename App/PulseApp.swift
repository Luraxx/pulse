import SwiftUI

@main
struct PulseApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        model.scheduleBackgroundRefresh()
                    case .active:
                        model.maybeShowJournalPrompt()
                    default:
                        break
                    }
                }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await model.performBackgroundRefresh()
        }
    }
}

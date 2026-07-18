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
                    if phase == .background {
                        model.scheduleBackgroundRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await model.performBackgroundRefresh()
        }
    }
}

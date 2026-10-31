import SwiftUI

@main
struct FactoryToolsWatchApp: App {
    @StateObject private var model = WatchCounterModel()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(model)
        }
    }
}

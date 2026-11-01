import SwiftUI

@main
struct FactoryToolsWatchApp: App {
    @StateObject private var model = WatchCounterModel()

    private var displayLocale: Locale {
        switch model.displayLanguage {
        case .system: .current
        case .japanese: Locale(identifier: "ja")
        case .english: Locale(identifier: "en")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(simulator)
            if let sessionID = model.screenshotDemoSessionID {
                NavigationStack {
                    WatchCounterDetailView(sessionID: sessionID)
                }
                .environmentObject(model)
                .environment(\.locale, displayLocale)
                .tint(WatchTheme.accent)
                .preferredColorScheme(.dark)
            } else {
                WatchHomeView()
                    .environmentObject(model)
            }
            #else
            WatchHomeView()
                .environmentObject(model)
            #endif
        }
    }
}

import SwiftUI

final class ThemeManager {
    func theme(for id: ThemeID) -> AppTheme {
        switch id {
        case .industrialDark: .industrialDark
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.industrialDark
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

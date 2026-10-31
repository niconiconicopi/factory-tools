import Foundation

enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case industrialDark = "industrial.dark"

    var id: String { rawValue }
}

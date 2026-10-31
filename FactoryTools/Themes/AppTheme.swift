import FactoryToolsCore
import SwiftUI

struct AppTheme {
    let id: ThemeID
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentForeground: Color
    let success: Color
    let warning: Color
    let critical: Color
    let border: Color
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let homeTitleFont: Font
    let cardTitleFont: Font
    let bodyFont: Font
    let subheadlineFont: Font
    let calloutFont: Font
    let captionFont: Font
    let actionFont: Font
    let smallCounterPointSize: CGFloat
    let regularCounterPointSize: CGFloat
    let menuIconFont: Font

    func counterFont(for size: ToolCardSize, smallScale: CGFloat, regularScale: CGFloat) -> Font {
        let pointSize = size == .small
            ? smallCounterPointSize * smallScale
            : regularCounterPointSize * regularScale
        return .system(size: pointSize, weight: .bold, design: .rounded).monospacedDigit()
    }

    static let industrialDark = AppTheme(
        id: .industrialDark,
        background: Color(red: 0.055, green: 0.067, blue: 0.078),
        cardBackground: Color(red: 0.105, green: 0.122, blue: 0.137),
        primaryText: Color(red: 0.93, green: 0.95, blue: 0.95),
        secondaryText: Color(red: 0.58, green: 0.64, blue: 0.67),
        accent: Color(red: 0.98, green: 0.55, blue: 0.16),
        accentForeground: Color(red: 0.055, green: 0.067, blue: 0.078),
        success: Color(red: 0.28, green: 0.78, blue: 0.53),
        warning: Color(red: 0.98, green: 0.72, blue: 0.22),
        critical: Color(red: 0.94, green: 0.31, blue: 0.28),
        border: Color.white.opacity(0.09),
        cornerRadius: 18,
        borderWidth: 1,
        homeTitleFont: .system(.title2, design: .default).weight(.semibold),
        cardTitleFont: .headline.weight(.semibold),
        bodyFont: .body,
        subheadlineFont: .subheadline,
        calloutFont: .callout.weight(.medium),
        captionFont: .caption,
        actionFont: .headline,
        smallCounterPointSize: 30,
        regularCounterPointSize: 48,
        menuIconFont: .title3
    )
}

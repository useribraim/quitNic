import SwiftUI

/// The canonical visual language used by Today, Journey, Rescue, and Coach.
/// Keeping these values here prevents each flow from inventing its own blue, surface,
/// corner radius, and action colour as the product evolves.
enum HorizonTheme {
    // The `musorka` references use a deliberately small, saturated print palette.
    // Keep it centralized: product screens should compose these colours, not invent
    // another translucent blue for every card.
    static let cobalt = Color(red: 0.025, green: 0.20, blue: 0.56)
    static let deepCobalt = Color(red: 0.018, green: 0.075, blue: 0.21)
    static let paper = Color(red: 0.96, green: 0.91, blue: 0.83)
    static let paperInk = Color(red: 0.025, green: 0.10, blue: 0.25)
    static let forest = Color(red: 0.025, green: 0.25, blue: 0.19)
    static let plum = Color(red: 0.29, green: 0.075, blue: 0.29)
    static let backgroundTop = cobalt
    static let backgroundBottom = deepCobalt
    static let surface = Color(red: 0.045, green: 0.13, blue: 0.31)
    static let readingSurface = Color(red: 0.025, green: 0.055, blue: 0.12)
    static let tabBarSurface = Color(red: 0.025, green: 0.035, blue: 0.07)
    static let breathingWarmth = Color(red: 1, green: 0.72, blue: 0.45)
    static let strongSurface = deepCobalt.opacity(0.94)
    static let border = paper.opacity(0.24)
    static let primaryText = Color.white
    // Body copy must remain readable on both the gradient and translucent cards.
    // 0.84 keeps the hierarchy softer than primary text without sacrificing contrast.
    static let secondaryText = Color.white.opacity(0.92)
    // Dark enough for white labels to clear WCAG contrast on filled controls.
    static let accent = Color(red: 0.76, green: 0.10, blue: 0.035)
    // Use for accent-coloured text on dark/translucent surfaces. The stronger brand
    // orange remains available for filled controls, icons and decorative borders.
    static let accentText = Color(red: 1, green: 0.78, blue: 0.59)
}

/// Shared layout primitives for the Horizon product surfaces. These are deliberately
/// few: compact control spacing, normal content spacing, and generous section spacing.
enum HorizonLayout {
    static let micro: CGFloat = 4
    static let tight: CGFloat = 6
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let content: CGFloat = 16
    static let section: CGFloat = 20
    static let roomy: CGFloat = 24
    static let spacious: CGFloat = 28
    static let hero: CGFloat = 40

    /// Content clearance for the persistent two-tab dock. Kept here rather than
    /// rediscovered as screen-local bottom padding.
    static let todayTabClearance: CGFloat = 82
    static let journeyTabClearance: CGFloat = 136

    static let controlRadius: CGFloat = 12
    static let panelRadius: CGFloat = 14
    static let hairline: CGFloat = 1
    static let emphasisBorder: CGFloat = 2
}

/// One typographic scale for the whole app. The licensed upright variable file keeps
/// the shipped font payload small while supporting the full weight axis.
enum HorizonType {
    private static let family = "SatoshiVariable-Bold_Regular"

    static func display(_ size: CGFloat) -> Font {
        .custom(family, size: size, relativeTo: .largeTitle)
    }

    static func body(_ style: Font.TextStyle = .body) -> Font {
        .custom(family, size: pointSize(for: style), relativeTo: style)
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

private struct QuitNicFontStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(HorizonType.body())
    }
}

struct HorizonCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)?

    var body: some View {
        Button("Close", systemImage: "xmark") {
            if let action { action() } else { dismiss() }
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.bold))
        .foregroundStyle(HorizonTheme.primaryText)
        .frame(width: 44, height: 44)
        .background(HorizonTheme.strongSurface, in: Circle())
        .buttonStyle(.plain)
        .accessibilityHint("Returns to Today")
        .accessibilityIdentifier("closeHorizonScreen")
    }
}

struct HorizonBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [HorizonTheme.backgroundTop, HorizonTheme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct HorizonCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(HorizonLayout.section)
            .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HorizonLayout.panelRadius, style: .continuous)
                    .strokeBorder(HorizonTheme.border, lineWidth: HorizonLayout.hairline)
            }
    }
}

struct HorizonPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HorizonLayout.content)
            .background(
                HorizonTheme.accent.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func horizonCard() -> some View {
        modifier(HorizonCardModifier())
    }

    func quitNicFontStyle() -> some View {
        modifier(QuitNicFontStyleModifier())
    }
}

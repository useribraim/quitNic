import SwiftUI
import UIKit

enum QuitNicTheme {
    static let navy = Color(red: 0.06, green: 0.15, blue: 0.24)
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.93, blue: 0.97, alpha: 1)
            : UIColor(red: 0.06, green: 0.15, blue: 0.24, alpha: 1)
    })
    static let teal = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.29, green: 0.82, blue: 0.72, alpha: 1)
            : UIColor(red: 0.02, green: 0.42, blue: 0.36, alpha: 1)
    })
    static let actionTeal = Color(red: 0.02, green: 0.42, blue: 0.36)
    static let mint = Color(red: 0.79, green: 0.94, blue: 0.87)
    static let warmBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
            : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    })
    static let warmSurface = Color(red: 1.00, green: 0.99, blue: 0.97)
    static let softBlue = Color(red: 0.88, green: 0.94, blue: 0.97)
}

struct QuitNicCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : QuitNicTheme.warmSurface,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            }
    }
}

extension View {
    func quitNicCard() -> some View {
        modifier(QuitNicCardModifier())
    }
}

struct QuitNicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                configuration.isPressed ? QuitNicTheme.actionTeal.opacity(0.82) : QuitNicTheme.actionTeal,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

import SwiftUI

enum UniOSTheme {
    static let tint = Color(red: 0.07, green: 0.42, blue: 0.65)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let quietText = Color(uiColor: .secondaryLabel)
    static let badge = Color(red: 0.83, green: 0.22, blue: 0.20)
    static let hero = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.33, blue: 0.55),
            Color(red: 0.11, green: 0.55, blue: 0.73),
            Color(red: 0.70, green: 0.82, blue: 0.90)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func avatarColor(hue: Double) -> Color {
        Color(hue: hue, saturation: 0.52, brightness: 0.82)
    }
}

private struct UniOSCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(UniOSTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func uniosCard() -> some View {
        modifier(UniOSCardModifier())
    }
}


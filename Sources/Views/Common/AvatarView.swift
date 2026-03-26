import SwiftUI

struct AvatarView: View {
    let initials: String
    let hue: Double
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(UniOSTheme.avatarColor(hue: hue))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}


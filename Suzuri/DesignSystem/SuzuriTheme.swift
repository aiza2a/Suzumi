import SwiftUI
import UIKit

enum SuzuriTheme {
    static let accent = Color.brand600
    static let background = adaptive(light: 0xF5F5F7, dark: 0x101013)
    static let paper = adaptive(light: 0xFFFFFF, dark: 0x1B1A1E)
    static let ink = adaptive(light: 0x201D24, dark: 0xF5F2F7)
    static let secondaryInk = adaptive(light: 0x625D66, dark: 0xBEB8C4)
    static let accentText = adaptive(light: 0xA83133, dark: 0xF19091)
    static let line = Color(uiColor: .separator).opacity(0.25)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(SuzuriTheme.accent.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

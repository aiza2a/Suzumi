import SwiftUI

/// Quiet surfaces keep long-form writing legible without continuous background rendering.
struct AppBackground: View {
    var body: some View {
        SuzuriTheme.background
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

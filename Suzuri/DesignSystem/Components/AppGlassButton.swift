import SwiftUI

/// 玻璃按钮（D4_plan §6）。
///
/// 主样式：`brand600` 填充 + 白字 + cornerRadius 14 + 按压 `scaleEffect(0.97)` + 阴影（GlassButton 反馈）。
/// 次级样式：`appGlass()` 材质 + `brand600` 文字。
struct AppGlassButton: View {
    enum Style: Equatable {
        case primary      // brand600 填充
        case secondary    // 玻璃材质 + brand600 文字
    }

    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void

    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(style == .primary ? .white : .brand600)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                if !isLoading {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(style == .primary ? Color.white : Color.brand600)
            .background(style == .primary ? primaryBackground : nil)
            .appGlass(cornerRadius: 14, allowsShadow: style == .primary)
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
        .animation(AppAnimation.pop, value: pressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            pressed = isPressing
        }, perform: {})
    }

    @ViewBuilder
    private var primaryBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.brand600, Color.brand700],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            )
    }
}

#Preview {
    ZStack {
        AppBackground()
        VStack(spacing: 14) {
            AppGlassButton(title: "发布", systemImage: "paperplane.fill") {}
            AppGlassButton(title: "存草稿", style: .secondary) {}
        }
        .padding(22)
    }
}
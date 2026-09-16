import SwiftUI

/// 空态视图（D4_plan §6）。
///
/// 图标（SF Symbol，brand400）+ 主文案（.secondary）+ 次文案（.tertiary），垂直居中。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.brand400)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        AppBackground()
        EmptyStateView(
            systemImage: "doc.text",
            title: "还没有文章",
            message: "在编辑器写下第一篇，发布后会出现在这里。")
    }
}
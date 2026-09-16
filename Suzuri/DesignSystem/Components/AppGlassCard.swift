import SwiftUI

/// 玻璃卡片容器（D4_plan §6）。
///
/// `content.padding(18).frame(maxWidth: .infinity, alignment: .leading).appGlass(cornerRadius: 28)`。
struct AppGlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let material: Material
    private let brandTint: Bool
    @ViewBuilder private var content: () -> Content

    init(cornerRadius: CGFloat = 28,
         material: Material = .ultraThinMaterial,
         brandTint: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.brandTint = brandTint
        self.content = content
    }

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appGlass(cornerRadius: cornerRadius, material: material, brandTint: brandTint)
    }
}

#Preview {
    ZStack {
        AppBackground()
        AppGlassCard {
            Text("GlassCard")
                .font(.title3.weight(.semibold))
            Text("统一玻璃表面，iOS 17/18 模拟层与 iOS 26 原生层等效。")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
}
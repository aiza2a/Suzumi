import SwiftUI

/// 全 App 统一玻璃表面 ViewModifier（D4_plan §3）。
///
/// iOS 17/18 模拟层：material 填充 + 白描边（brandTint 时换品牌色）+
/// 左上 RadialGradient 高光 softLight + 阴影；ReduceTransparency 退化为纯色。
/// iOS 26 叠加原生 `.glassEffect()`（编译期分支，模拟层与原生层共用同一套参数，切换无感知）。
struct AppGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    var material: Material = .ultraThinMaterial
    var brandTint: Bool = false              // 选中/焦点态描边换品牌色
    var allowsShadow: Bool = true

    @Environment(\.colorScheme) private var cs
    @Environment(\.accessibilityReduceTransparency) private var reduce

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduce
                        ? AnyShapeStyle(Color(.secondarySystemBackground).opacity(cs == .dark ? 0.86 : 0.72))
                        : AnyShapeStyle(material))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(brandTint ? Color.brand600.opacity(0.55)
                                      : Color.white.opacity(cs == .dark ? 0.22 : 0.18),
                            lineWidth: brandTint ? 1.2 : 1)
            }
            .overlay {
                // 左上高光 "lensing" —— 玻璃感灵魂
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(cs == .dark ? 0.16 : 0.14), .clear],
                        center: .topLeading, startRadius: 16, endRadius: 260))
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(allowsShadow ? (cs == .dark ? 0.35 : 0.10) : 0),
                    radius: allowsShadow ? 16 : 0, x: 0, y: allowsShadow ? 6 : 0)
            .suzuriGlassEffectIfAvailable(cornerRadius: cornerRadius)
    }
}

extension View {
    /// 应用统一玻璃表面。
    func appGlass(cornerRadius: CGFloat = 22,
                  material: Material = .ultraThinMaterial,
                  brandTint: Bool = false,
                  allowsShadow: Bool = true) -> some View {
        modifier(AppGlassSurface(cornerRadius: cornerRadius,
                                 material: material,
                                 brandTint: brandTint,
                                 allowsShadow: allowsShadow))
    }
}

extension View {
    /// iOS 26+ 原生液态玻璃，旧系统保留模拟层。
    @ViewBuilder
    func suzuriGlassEffectIfAvailable(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
        }
    }
}

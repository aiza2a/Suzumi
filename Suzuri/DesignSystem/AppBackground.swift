import SwiftUI

/// 编辑器/列表统一背景：带色相基底 + 慢呼吸品牌色光斑 + 顶部微光。
///
/// 三层（v3 设计文档 §1.1）：
/// - L1 基底渐变：暗色黑中带褐红 / 亮色暖白，拒绝纯灰平涂。
/// - L2 品牌色光斑：`MorphingBlob` 随 TimelineView 极慢呼吸（~20s 周期），
///   暗色 `plusLighter` 发光、亮色 `normal` 染色；ReduceMotion 时退化为静态相位。
/// - L3 顶部微光带：苹果卡片式高光来源。
struct AppBackground: View {
    @Environment(\.colorScheme) private var cs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // L1 基底
            LinearGradient(
                colors: cs == .dark
                    ? [Color(red: 0.07, green: 0.06, blue: 0.08), Color(red: 0.03, green: 0.03, blue: 0.04)]
                    : [Color(red: 0.99, green: 0.98, blue: 0.97), Color(red: 0.96, green: 0.95, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            // L2 品牌色光斑
            if reduceMotion {
                StaticBlob(cs: cs)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    MorphingBlob(phase: t * 0.05, amplitude: 0.15, points: 14)
                        .fill(LinearGradient(
                            colors: [.brand600.opacity(cs == .dark ? 0.22 : 0.10),
                                     .brand300.opacity(cs == .dark ? 0.10 : 0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 460, height: 460)
                        .blur(radius: 60)
                        .offset(x: 180, y: -280)
                        .blendMode(cs == .dark ? .plusLighter : .normal)
                }
            }

            // L3 顶部微光
            LinearGradient(colors: [.white.opacity(0.5), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
                .blendMode(.softLight)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// ReduceMotion 退化层：固定相位，只渲染一帧。
private struct StaticBlob: View {
    let cs: ColorScheme

    var body: some View {
        MorphingBlob(phase: 1.2, amplitude: 0.15, points: 14)
            .fill(LinearGradient(
                colors: [.brand600.opacity(cs == .dark ? 0.22 : 0.10),
                         .brand300.opacity(cs == .dark ? 0.10 : 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 460, height: 460)
            .blur(radius: 60)
            .offset(x: 180, y: -280)
            .blendMode(cs == .dark ? .plusLighter : .normal)
    }
}

#Preview {
    ZStack {
        AppBackground()
        Text("Preview")
            .foregroundStyle(.primary)
    }
}
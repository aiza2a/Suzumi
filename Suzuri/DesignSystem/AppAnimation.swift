import SwiftUI

/// 统一曲线来源（D4_plan §5）。全 App 唯一动画入口，禁止散落 `Animation.linear` 长动画。
enum AppAnimation {
    /// 块焦点迁移：触感轻快不拖沓。
    static let blockFocus = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// 列表/块插入删除：稍软，避免跳变。
    static let listInsert = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// 弹出/按压回弹。
    static let pop = Animation.easeInOut(duration: 0.2)
    /// 慢速淡入淡出。
    static let fadeSlow = Animation.easeInOut(duration: 0.3)
}

extension View {
    /// 出现/消失统一过渡：opacity + scale，符合 v3 动画纪律。
    static var appAppearanceTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }
}
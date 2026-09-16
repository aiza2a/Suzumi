import SwiftUI

/// 应用根视图入口。
///
/// D1 阶段此处为发布 Debug 界面；D4 起视觉系统就绪后委托 `EditorScreen`。
/// 保留此类型作为 `SuzuriApp` 的入口点，便于后续接入 Tab 路由。
struct RootView: View {
    var body: some View {
        EditorScreen()
    }
}
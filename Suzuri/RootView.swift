import SwiftUI

/// 应用根视图入口：启动时显示文章列表。
///
/// 新建按钮与文章编辑流程由 `PageListView` 继续进入 `EditorScreen`。
@MainActor
struct RootView: View {
    @State private var sessionController = SessionController()
    @State private var draftStore = DraftStore()

    var body: some View {
        PageListView(
            sessionController: sessionController,
            draftStore: draftStore
        )
    }
}

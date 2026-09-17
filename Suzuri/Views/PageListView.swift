import SwiftUI

/// 已发布文章列表（D4 骨架，D5 接入数据）。
///
/// 玻璃卡片列表：标题 + 摘要 + 浏览量（`.monospacedDigit`）+ 日期；
/// 下拉刷新占位；无数据时展示 `EmptyStateView`。
struct PageListView: View {
    @State private var isRefreshing: Bool = false

    // D5 接入真实数据；当前骨架用空数组触发空态。
    private var pages: [PageRowPreview] { PageRowPreview.samples }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(pages) { page in
                        PageRowView(page: page)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refresh()
            }
            .overlay {
                if pages.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.text",
                        title: "还没有文章",
                        message: "在编辑器写下第一篇，发布后会出现在这里。")
                }
            }
        }
        .navigationTitle("文章")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refresh() async {
        isRefreshing = true
        // D5: 拉取 getPageList
        try? await Task.sleep(nanoseconds: 400_000_000)
        isRefreshing = false
    }
}

/// 单行文章卡片（D5 接入 TelegraphPage 实体后改字段）。
private struct PageRowView: View {
    let page: PageRowPreview

    var body: some View {
        AppGlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(page.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(page.views)", systemImage: "eye")
                        .monospacedDigit()
                    Text(page.dateText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)   // 纯装饰箭头
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)   // 标题/摘要/元信息合并为一个可读元素
            }
        }
    }
}

/// D5 数据层占位（D5 替换为真实 TelegraphPage 映射）。
struct PageRowPreview: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let views: Int
    let dateText: String

    static let samples: [PageRowPreview] = []   // 骨架期空 → 触发空态
}

#Preview("Empty") {
    NavigationStack { PageListView() }
}
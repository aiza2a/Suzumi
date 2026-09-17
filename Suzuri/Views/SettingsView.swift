import SwiftUI

/// 设置页（D4 骨架，D5 接入实际配置与持久化）。
///
/// 四组占位：账号 / 图床 / 服务器 / 关于。
struct SettingsView: View {
    var body: some View {
        ZStack {
            AppBackground()
            Form {
                accountSection
                imageHostSection
                serverSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountSection: some View {
        Section {
            settingsRow(title: "当前账号", value: "匿名（D5 接入）")
            settingsRow(title: "切换账号", value: nil, showsChevron: true)
        } header: {
            Text("账号")
        }
    }

    private var imageHostSection: some View {
        Section {
            settingsRow(title: "图床", value: "QuAx（默认）", showsChevron: true)
            settingsRow(title: "压缩质量", value: "0.85", showsChevron: true)
        } header: {
            Text("图床")
        } footer: {
            Text("D5：Telegraph-Image 自部署 + Basic Auth 联调。")
        }
    }

    private var serverSection: some View {
        Section {
            settingsRow(title: "服务器镜像", value: "telegra.ph", showsChevron: true)
            settingsRow(title: "自定义 baseURL", value: nil, showsChevron: true)
        } header: {
            Text("服务器")
        } footer: {
            Text("telegra.ph / graph.org / legra.ph 三选 + 自定义。")
        }
    }

    private var aboutSection: some View {
        Section {
            settingsRow(title: "版本", value: "0.1.0")
            settingsRow(title: "开源许可", value: nil, showsChevron: true)
        } header: {
            Text("关于")
        }
    }

    private func settingsRow(title: String, value: String?, showsChevron: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
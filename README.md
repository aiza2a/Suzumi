# Suzuri · 硯

在 iPhone 上写作、保存草稿、配图并发布 Telegraph 文章的客户端。SwiftUI + UIKit，最低 iOS 17。

## 0.2.0 重构预览

- 全页文稿画布：标题与正文统一滚动，底部工具栏提供段落样式、插入、图片、排序和多选。
- 文章库：草稿/已发布分类、标题搜索、本地自动保存与保存失败提示。
- 账号：从 Telegram 的 @telegraph 取得官方登录链接后连接已有账号，也支持 API token 导入。首次直接发布仍可创建匿名账号。
- 图片：默认 Postimages，使用官方网页选择图片、完成验证，再粘贴 Direct link 插入文章。自定义兼容图床可选；不再默认使用 qu.ax，也不自动切换到其他图片服务。
- 配色：#BE4041 朱红重点色，中性浅色纸面与暗色阅读背景；适配系统字体大小。
- 可靠性：编辑合并同步、组合输入保护、多图内容只读、草稿作用域、迟到账号请求、显式存储失败处理。

## 获取测试包

开发分支：`codex/suzuri-usability-redesign`。本分支未经用户确认不会合并 main。

推送后，Build IPA 和 iOS Tests 独立运行。编译成功即在 Releases 创建预发布并提供未签名 IPA，测试不阻塞下载。IPA 需要用自己的签名通过侧载工具安装；并非 TestFlight 包。

[预发布下载](https://github.com/aiza2a/Suzumi/releases) · [Actions](https://github.com/aiza2a/Suzumi/actions)

## 验证

XcodeGen：`xcodegen generate`。在 macOS 使用 Xcode 打开生成的工程，运行 Suzuri scheme。

- 自动测试覆盖模型、存储、请求、URL 边界与 UIKit 编辑同步。
- 真实 Telegram 授权、Postimages 上传与键盘布局需在设备上验收；编译成功本身不代表这些外部流程已验证。
- 编辑器暂不渲染行内富文本，不支持无损转换的远端结构会阻止覆盖发布。

实现依据与验收清单见 [外部服务](docs/external-services.md)、[CI](docs/ci.md)、[重构验收](docs/redesign-validation.md)。参考源码位于仓库外的只读目录，未复制进入产品仓库。

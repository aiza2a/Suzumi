# 编译、测试与预览下载

编译和测试使用独立的 GitHub Actions 工作流，并行运行。打包与发布不等待 XCTest，构建成功不代表测试通过；查看测试结果时，应核对相同的提交 SHA。

## 未签名预览包

`.github/workflows/ios-build.yml` 在 `main`、`codex/suzuri-usability-redesign` 推送、`v*` 标签推送或手动触发时编译。它检出触发事件对应的精确 SHA，生成 `Suzuri-unsigned.ipa` 并保存为 Actions artifact。

当运行分支为 `codex/suzuri-usability-redesign` 时，构建成功后还会创建 GitHub 预发布版本，标签为 `suzuri-preview-运行编号-重试编号`。预发布标签指向本次编译的精确 SHA，附件可以从仓库 Releases 页面下载。创建预发布不会合并 `main`。

IPA 未签名，使用前必须通过侧载工具和自己的签名账号重新签名，不能直接从浏览器安装。只有打包作业申请仓库内容写权限，用于上传预发布附件。

## 独立测试

`.github/workflows/ios-tests.yml` 在 PR、上述两个分支推送或手动触发时运行，并保留 `workflow_call` 入口供需要时复用。它自动选择已安装且可用的 iPhone 模拟器，执行 `xcodebuild test`，上传 `.xcresult` 与测试日志。测试失败会显示在自己的工作流中，不阻止预览 IPA 生成。

## 正式签名发布

`.github/workflows/ios-release.yml` 仍只允许手动运行，要求 `main`、`RELEASE_ENABLED=true`、签名证书和 App Store Connect 凭据。该工作流也与测试独立，未配置签名条件时不会发布 TestFlight。

所有工作流沿用项目现有的 `macos-15` runner 和 Xcode `26.3` 配置；可用性以实际 Actions 日志为准。

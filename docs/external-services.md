# 外部服务接入依据与验收边界

核对日期：2026-10-07。所有工作均在 `codex/suzuri-usability-redesign` 分支。研究阶段只读取公开网页和参考源码，没有上传图片、登录真实账号、创建账号或发布内容。

## Postimages

当前采用站内浏览器打开官方上传页，用户通过网页选择图片，上传后复制 **Direct link** 到上方输入框，明确点击“插入”。只接受 `https://i.postimg.cc/…/文件名.图片扩展名`；拒绝展示页、论坛代码、HTTP、用户名密码、非默认端口和相似域名。上传完成后插入文章的是图片直链，而不是 Postimages 展示页。

选择该路径的依据：

- [官方首页](https://postimages.org/) 当前表单为 `POST /json`，页面包含图片尺寸和失效时间选项。
- [官方网页脚本](https://postimgs.org/4160/s.js) 动态创建标准 `input type=file`，使用 `FormData` / XHR 上传，集成 hCaptcha；成功回调使用 `url` 重定向，并用 `image` 打开展示链接。这是站点内部实现，不是已验证的长期公共 API 契约。
- 首页目前宣传 API access，但本次读取 [API 路径](https://postimages.org/api) 只返回 HTTP 200 和空正文，未取得认证方式、请求和直链响应规范。因此没有伪造原生 Postimages API，也没有在失败时把用户图片发送到其他图床。
- 脚本会在上传成功后跳转，并对单图使用 `target=_blank`。WebView 允许 Postimages / Postimg 的精确 HTTPS 主机，单图新窗口在当前窗口打开；第三方广告顶层跳转不会接管页面。
- [WebKit 的 iOS 文件上传实现](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm) 使用 PHPicker、UIDocumentPicker 等系统选择器。我们保留标准网页文件输入，不注入图片数据，不读取本地照片库。

还需在 iOS 真机验证：网页“Choose images”能否打开系统文件/图片选择器；用户取消选择；hCaptcha（如出现）；上传后 `postimg.cc` 跳转；复制 Direct link；插入后图片加载和发布；断网时错误提示与重新加载。上述静态实现依据不等同于完成实机上传验收。

## Telegram / Telegraph

授权入口打开 [@telegraph](https://t.me/telegraph)，由用户选择已有 Telegraph 账号、复制该账号的登录链接，再粘贴回 Suzuri。它不是 Telegram 手机号或短信登录，也不会读取 Telegram 聊天记录。

- [Telegraph 官方 API 文档](https://telegra.ph/api) 将 `auth_url` 定义为授权浏览器进入 Telegraph 账号的 URL，有效期 5 分钟且只可使用一次。`getAccountInfo` 是确认 API access token 对应账号的官方方法。
- [Telegraph 官方网页脚本](https://telegra.ph/js/core.min.js?67) 的 `checkAuth` 使用浏览器 cookie 调用 `https://edit.telegra.ph/check`。脚本不公开 cookie 名称，也没有声明浏览器 cookie 与 API access token 的兼容契约。
- 本地参考 `Suzuri_references/telegraph-android` 的 `UserRepository.login` 请求授权链接，`AuthInterceptor` 取第二个 `Set-Cookie` 的值作为 API token；README 明确支持 Telegram bot 授权同步。参考项目证明其采用过“授权链接 → cookie → API token”流程，但按 cookie 顺序取值不可靠，不能当成官方稳定协议。
- 参考目录没有 `.git`，无法通过本地提交历史进一步验证 cookie 名称。公开匿名页面也没有返回已登录账号的 cookie；本轮不能声称已验证 `tph_token` 名称及其与 API token 的兼容性。

安全约束：只接受 `https://edit.telegra.ph/auth/…` 或 `https://telegra.ph/auth/…`；拒绝其他域名、附加查询、凭据、端口；每次使用全新的非持久 WebView 数据存储，避免失效链接误导入旧账号；凭据只在官方 Telegraph 站点流转，不写入日志。最终账号导入必须经过官方 API 验证，成功后由 SessionController 保存到钥匙串。

实现不将 `tph_token` 当作固定协议：它只影响候选排序。只从精确官方域名的 Secure、未过期 cookie 收集去重候选值，交给既有 SessionController 官方 API 校验流程。只有服务器明确返回 `ACCESS_TOKEN_INVALID` 才继续下一个候选；网络、取消、存储错误和账号/服务器变化立即停止并展示错误。所有候选均被拒绝时显示失败，不保存未经验证的 cookie，也不假定授权成功。

还需真机验收：新链接、已使用链接、过期链接、多个 bot 账号分别连接、取消连接、网络错误、切换 API 服务器期间响应迟到、连接后文章列表归属。Cookie/API 桥接仍属于兼容性接入，必须用真实账号确认后才能标记授权功能验收通过。

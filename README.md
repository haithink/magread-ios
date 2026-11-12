# 刊读 · iOS

把原版英文刊物装进口袋。导入自己的 EPUB / PDF，在原文旁学习词语、理解句子，并与 AI 讨论正在阅读的内容。

原生 **SwiftUI + PDFKit**，支持 **iOS 17 及以上**的 iPhone / iPad。本项目与 [安卓版](https://github.com/haithink/magread)、[Windows 桌面版](https://github.com/haithink/magread-desktop)、[Chrome 插件](https://github.com/haithink/magread-chrome)分别维护；这是 iOS 首版，并非其他版本的完整功能移植。

## 已实现

- **本地书架**：通过“文件”导入 EPUB / PDF，提取封面，显示最近阅读。
- **EPUB 阅读**：按原书 spine 章节组织目录；未读 / 已读 / 不感兴趣标记；逐篇生成中文摘要；正文字号调整、选择文本、搜索；恢复段落位置。
- **PDF 阅读**：PDFKit 保留原始排版，连续翻页、缩放、跳转页码，恢复上次阅读位置。
- **AI 辅助**：段落生词与短语、句子 / 段落讲解、文章问答；PDF 选中文字或当前页正文问答。会话保存在设备本地。
- **个人生词本**：词表一键收藏，搜索、手动添加、编辑和删除；当前段落中出现的个人生词会补充展示。
- **自选模型**：OpenAI 兼容协议（默认示例为 DeepSeek）、Anthropic；流式阶段 / 字数 / 耗时显示，支持取消，结果本地缓存。

EPUB 的目录粒度取决于出版物原始结构，一个文件中包含多篇文章时暂不额外自动拆分。PDF 按页阅读，暂不支持 PDF 文章自动切分、扫描页 OCR 或图片提问。摘要只在目录长按指定文章后手动生成；不在导入时批量调用模型。生词由模型按水平与语境判断，没有内置来源不明的四级词库。

## 获取安装包

1. 打开仓库的 **Actions → Build iOS**，进入最近一次成功运行。
2. 在页面底部 **Artifacts** 下载 `MagRead-iOS-unsigned`，解压外层 ZIP，得到 `MagRead-unsigned.ipa`。下载 Actions 附件通常需要登录 GitHub。
3. 在 Windows 上使用你自己的 iLoader 导入 IPA，完成签名和安装。这里提供的是**未签名的真机安装包**，需要签名后才能打开。
4. iPhone 若提示需要开发者模式，按照系统提示开启；安装 / 续签有效期取决于使用的 Apple 签名方式。不要把 Apple ID 密码、证书或描述文件上传到本仓库。

云端构建使用公开仓库的标准 macOS runner，不需要为此项目配置 Apple 证书或 GitHub Secrets。此流程不自动发布 App Store / TestFlight。

首次安装后，在 **设置** 填写自己的 HTTPS API 地址、模型名和 API Key，保存并测试连接；再从书架导入刊物。PDF 中可先选中文字再打开“阅读问答”，不选择时使用当前页可提取的文本。

## 数据与隐私

- **没有内置 API Key**。API Key 仅存入 iOS Keychain，配置 JSON 明确排除此字段。
- 导入文件、阅读进度、词表和会话保存在应用沙盒；本项目没有运营服务器，也没有遥测代码。
- 使用 AI 功能时，相关原文与近期会话会发送至**你配置的模型服务**，并产生该服务的正常费用。仅本地阅读不调用模型。
- 源码仓库与构建产物不包含用户刊物、阅读记录、密钥或签名证书。
- 请自行备份重要数据；本版尚无跨设备同步、导出与数据迁移功能。

## 开发与验证

Windows 可以编辑源代码、提交和触发 GitHub Actions；编译 iOS 和运行模拟器需要 macOS + Xcode。

在装有 Xcode 16.4 的 Mac 上：

```sh
brew install xcodegen
xcodegen generate
open MagRead.xcodeproj
```

工程由 `project.yml` 生成，不提交生成的 Xcode 工程。SwiftPM 依赖固定版本：ZIPFoundation 0.9.20、SwiftSoup 2.14.3。CI 先在 iPhone 模拟器运行测试，再编译 arm64 真机版本并打包 IPA。单元测试使用合成 EPUB 和模拟响应，不读取真实书籍，不访问付费 API。

修改用户功能时同步更新 [CHANGELOG.md](CHANGELOG.md)。目前没有宣称完成真实 iPhone 安装验证；请以 Actions 编译 / 测试结果与实际侧载体验分别判断。

## 开源许可

项目采用 [MIT License](LICENSE)。设计参考 MIT 许可的刊读 Android 版，以原生 Swift 重新实现；未复制桌面版 AGPL 代码。第三方依赖的许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，并随应用附带。请仅导入你有权使用的出版物，书籍本身不在本项目许可范围内。

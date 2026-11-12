# 版本记录

## 0.1.0 — 2026-11-12

- 新建原生 SwiftUI iOS 项目，最低支持 iOS 17，适配 iPhone 和 iPad。
- 本地导入 EPUB / PDF，提取封面，保存最近阅读和段落 / 页码进度。
- EPUB 章节目录支持未读、已读、不感兴趣筛选，以及逐篇生成中文摘要。
- EPUB 正文支持字号调整、文本选择、搜索和段落定位。
- 段落生词 / 短语讲解、个人生词本增删改查。
- 文章及 PDF 当前页文本问答，按阅读材料保存会话。
- 支持 OpenAI 兼容及 Anthropic 协议，API 密钥通过 iOS Keychain 保存。
- 流式响应进度、耗时、取消；DeepSeek 关闭额外思考；正常 JSON 响应直接读取。
- GitHub Actions 使用 macOS 构建，运行单元测试并生成供自行签名的 unsigned IPA。

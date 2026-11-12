import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var job = GenerationJob()
    @State private var draft = LLMConfiguration()
    @State private var notice: String?
    @State private var loaded = false
    var body: some View {
        Form {
            Section("模型服务") {
                Picker("协议", selection: $draft.provider) {
                    ForEach(Provider.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                }
                TextField("API 地址（HTTPS）", text: $draft.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("模型名称", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key", text: $draft.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("密钥仅存于此 iPhone 的钥匙串，不会写入代码、Git 仓库或安装包。阅读内容仅在你使用 AI 功能时发送至上方配置的服务。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("阅读偏好") {
                Picker("掌握词汇", selection: $draft.level) {
                    ForEach(["高中", "四级", "六级", "托福 / 雅思"], id: \.self) { Text($0).tag($0) }
                }
                Text("词表由模型结合语境筛选，包含熟词僻义和短语；个人生词本中的原词也会展示。")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: settings.$fontSize, in: 14...30, step: 1) { Text("正文字号") }
                Text("正文字号：\(Int(settings.fontSize))").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("保存设置") {
                    do { try settings.save(draft); notice = "设置已保存。" }
                    catch { notice = error.localizedDescription }
                }
                Button("测试连接") {
                    job.run(config: draft, messages: [ChatMessage(role: "user", content: "请只回复：连接成功")], tokens: 64) { notice = $0 }
                }.disabled(job.running)
                JobProgressView(job: job)
                if let notice { Text(notice).font(.callout).textSelection(.enabled) }
            }
            Section("关于") {
                LabeledContent("刊读 iOS", value: "0.1.0")
                NavigationLink("开源许可") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "见源码仓库 THIRD_PARTY_NOTICES.md")
                            .font(.caption).textSelection(.enabled).padding()
                    }.navigationTitle("开源许可")
                }
                Text("本地导入 · 本地保存 · 自选模型\nEPUB 按原始章节组织；PDF 按页阅读。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .onAppear { if !loaded { draft = settings.config; loaded = true } }
        .onDisappear { job.cancel() }
    }
}

struct WordbookView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var editing: SavedWord?
    @State private var adding = false
    private var filtered: [SavedWord] {
        library.words.filter { query.isEmpty || $0.entry.word.localizedCaseInsensitiveContains(query) || $0.entry.meaning.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            if filtered.isEmpty { ContentUnavailableView("生词本为空", systemImage: "character.book.closed", description: Text("在段落词表中点击 ＋ 收藏，或手动添加。")) }
            ForEach(filtered) { word in
                Button { editing = word } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(word.entry.word).font(.headline)
                            Text(word.entry.phonetic).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(word.entry.meaning).font(.subheadline).foregroundStyle(.primary)
                        if !word.source.isEmpty { Text(word.source).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.padding(.vertical, 5)
                }.tint(.primary)
                    .swipeActions { Button("删除", role: .destructive) { library.removeWord(word.id) } }
            }
        }
        .searchable(text: $query, prompt: "搜索单词或释义")
        .navigationTitle("个人生词本")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(item: $editing) { word in NavigationStack { WordEditor(original: word) } }
        .sheet(isPresented: $adding) { NavigationStack { WordEditor() } }
    }
}

struct WordEditor: View {
    var original: SavedWord?
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry = VocabularyEntry(word: "", phonetic: "", meaning: "", context: "", root: "", isPhrase: false)
    var body: some View {
        Form {
            TextField("单词 / 短语", text: $entry.word).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("音标", text: $entry.phonetic)
            TextField("中文释义", text: $entry.meaning, axis: .vertical)
            TextField("原文语境", text: $entry.context, axis: .vertical)
            TextField("词根与词源", text: $entry.root, axis: .vertical)
            Toggle("短语", isOn: $entry.isPhrase)
        }
        .navigationTitle(original == nil ? "添加生词" : "编辑生词")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    entry.word = entry.word.trimmed
                    if let original, original.entry.id != entry.id { library.removeWord(original.id) }
                    library.add(entry, source: original?.source ?? "手动添加")
                    dismiss()
                }.disabled(entry.word.trimmed.isEmpty || entry.meaning.trimmed.isEmpty)
            }
        }
        .onAppear { if let original { entry = original.entry } }
    }
}

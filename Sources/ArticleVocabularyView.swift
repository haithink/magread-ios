import SwiftUI

struct ArticleVocabularyView: View {
    let book: Publication
    let article: Article
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var job = GenerationJob()
    @State private var search = ""
    @State private var filter = "全部"
    private var cache: [String: [VocabularyEntry]] { library.record(book, article.id).vocabulary }
    private var total: Int { ArticleVocabulary.sections(article).count }
    private var completed: Int { ArticleVocabulary.completed(article, level: settings.config.level, cache: cache) }
    private var items: [ArticleVocabularyItem] {
        ArticleVocabulary.items(article, level: settings.config.level, cache: cache, personal: library.words.map(\.entry))
    }
    private var filtered: [ArticleVocabularyItem] {
        items.filter {
            (filter == "全部" || (filter == "短语" ? $0.entry.isPhrase : !$0.entry.isPhrase)) &&
            (search.trimmed.isEmpty || $0.entry.word.localizedCaseInsensitiveContains(search) || $0.entry.meaning.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title).font(.headline).lineLimit(2)
                HStack {
                    Text("\(settings.config.level)基线 · \(items.count) 个词条")
                    Spacer()
                    Text("\(completed)/\(total) 处完成")
                }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                ProgressView(value: Double(completed), total: Double(max(1, total)))
                if completed == total {
                    Text("已覆盖全文与标题。相同释义合并展示，点击 ＋ 收藏。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("包含标题、生词、短语及熟词僻义。已完成的段落自动保存，取消后可继续。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                JobProgressView(job: job)
                if !job.running && completed < total {
                    Button(completed == 0 ? "一键生成整篇生词表" : "继续生成剩余 \(total - completed) 处") { generate() }
                        .buttonStyle(.borderedProminent)
                }
                Picker("词条类型", selection: $filter) {
                    Text("全部").tag("全部")
                    Text("单词").tag("单词")
                    Text("短语").tag("短语")
                }.pickerStyle(.segmented)
            }.padding(18).background(.background)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if filtered.isEmpty && !job.running {
                        ContentUnavailableView(completed == total && items.isEmpty ? "未发现需要补充的生词" : "暂无匹配词条",
                                               systemImage: "character.book.closed")
                    }
                    ForEach(filtered) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.location)
                                Spacer()
                                if item.personal { Text("个人生词") }
                            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                            VocabularyCard(entry: item.entry, source: article.title)
                        }
                    }
                }.padding(18)
            }
        }
        .background(Color.paper)
        .navigationTitle("整篇生词表").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索单词、短语或释义")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("重新生成整篇生词表") { generate(reset: true) }.disabled(job.running)
                } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("重新生成")
            }
        }
        .task { if completed < total { generate() } }
        .onDisappear { job.cancel() }
    }

    private func generate(reset: Bool = false) {
        guard !job.running else { return }
        let configuration = settings.config
        if reset {
            library.update(book, article.id) { record in
                for section in ArticleVocabulary.sections(article) {
                    record.vocabulary.removeValue(forKey: ArticleVocabulary.cacheKey(level: configuration.level, paragraph: section.index))
                }
            }
        }
        let existing = cache
        job.perform { job in
            try await ArticleVocabulary.generate(article: article, level: configuration.level, cache: existing) { batch in
                let prompt = try ArticleVocabulary.prompt(batch, level: configuration.level)
                let response = try await LLMClient.shared.chat(config: configuration, system: Prompts.tutor,
                    messages: [ChatMessage(role: "user", content: prompt)], tokens: 6000) { value in
                    await job.report(value)
                }
                return try ArticleVocabulary.decode(response, expected: batch)
            } save: { paragraph, entries in
                library.update(book, article.id) {
                    $0.vocabulary[ArticleVocabulary.cacheKey(level: configuration.level, paragraph: paragraph)] = entries
                }
                library.flush()
            }
        }
    }
}

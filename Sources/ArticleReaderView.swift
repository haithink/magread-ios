import SwiftUI

enum ReaderSheet: String, Identifiable {
    case vocabulary, explain, chat, wordbook
    var id: String { rawValue }
}

struct ArticleReaderView: View {
    let book: Publication
    let article: Article
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var sheet: ReaderSheet?
    @State private var selectedParagraph = 0
    @State private var visibleParagraph: Int?
    @State private var restored = false
    @State private var search = ""
    @State private var searchVisible = false
    @State private var resultIndex = 0
    private var matches: [Int] {
        guard !search.trimmed.isEmpty else { return [] }
        return article.paragraphs.indices.filter { article.paragraphs[$0].localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if searchVisible { searchBar }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        VStack(alignment: .leading, spacing: 12) {
                            if index == 0 {
                                Text(article.title).font(.system(.title, design: .serif, weight: .bold)).foregroundStyle(Color.ink)
                                Text("\(article.wordCount) 词 · \(article.paragraphs.count) 段")
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider().padding(.vertical, 6)
                            }
                            Text(highlighted(paragraph))
                                .font(.system(size: settings.fontSize, design: .serif))
                                .lineSpacing(8).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 18) {
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                Spacer()
                                Button { selectedParagraph = index; sheet = .vocabulary } label: { Label("生词 / 短语", systemImage: "character.book.closed") }
                                Button { selectedParagraph = index; sheet = .explain } label: { Label("讲解", systemImage: "text.bubble") }
                            }.font(.caption).buttonStyle(.borderless)
                        }.id(index)
                    }
                    Button("标记为已读") { library.update(book, article.id) { $0.status = .read } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(.bottom, 30)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 22).padding(.vertical, 24)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $visibleParagraph, anchor: .top)
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle(article.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .chat } label: { Image(systemName: "bubble.left.and.bubble.right") }.accessibilityLabel("文章问答")
                Menu {
                    Button("搜索正文", systemImage: "magnifyingglass") { searchVisible.toggle() }
                    Button("个人生词本", systemImage: "character.book.closed") { sheet = .wordbook }
                    ControlGroup {
                        Button("缩小字号") { settings.fontSize = max(14, settings.fontSize - 1) }
                        Button("放大字号") { settings.fontSize = min(30, settings.fontSize + 1) }
                    }
                    ForEach(ReadingStatus.allCases, id: \.rawValue) { status in
                        Button("标记为\(status.rawValue)") { library.update(book, article.id) { $0.status = status } }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task {
            guard !restored else { return }
            let saved = library.record(book, article.id).paragraph
            visibleParagraph = min(max(0, saved), max(0, article.paragraphs.count - 1))
            restored = true
            library.progress(book, article: article.id, paragraph: visibleParagraph)
        }
        .onChange(of: visibleParagraph) { _, index in
            if restored, let index { library.progress(book, article: article.id, paragraph: index) }
        }
        .sheet(item: $sheet) { kind in
            NavigationStack {
                Group {
                    switch kind {
                    case .vocabulary:
                        VocabularyView(book: book, article: article, paragraph: selectedParagraph)
                    case .explain:
                        ConversationView(book: book, articleID: article.id,
                                         context: article.paragraphs[selectedParagraph],
                                         title: "句子与段落讲解", storageSuffix: ":explain:\(selectedParagraph)",
                                         initialPrompt: "请翻译并讲解这一段的句子结构、语法和难点。按句解释，使用列表，不使用空格排列成分。")
                    case .chat:
                        ConversationView(book: book, articleID: article.id,
                                         context: "标题：\(article.title)\n" + article.paragraphs.joined(separator: "\n").prefixText(16000), title: "文章问答")
                    case .wordbook: WordbookView()
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { sheet = nil } } }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索本文", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: search) { _, _ in resultIndex = 0; jump() }
            Text(matches.isEmpty ? "0" : "\(resultIndex + 1)/\(matches.count)").font(.caption.monospacedDigit())
            Button { resultIndex = (resultIndex - 1 + matches.count) % max(1, matches.count); jump() } label: { Image(systemName: "chevron.up") }.disabled(matches.isEmpty)
            Button { resultIndex = (resultIndex + 1) % max(1, matches.count); jump() } label: { Image(systemName: "chevron.down") }.disabled(matches.isEmpty)
            Button { searchVisible = false; search = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
        }.padding(12).background(.thinMaterial)
    }
    private func jump() {
        if matches.indices.contains(resultIndex) { visibleParagraph = matches[resultIndex] }
    }
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !search.trimmed.isEmpty else { return result }
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: search, options: .caseInsensitive, range: range), !found.isEmpty {
            if let attributedRange = Range(found, in: result) { result[attributedRange].backgroundColor = .yellow.opacity(0.35) }
            range = found.upperBound..<text.endIndex
        }
        return result
    }
}

struct VocabularyView: View {
    let book: Publication
    let article: Article
    let paragraph: Int
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var job = GenerationJob()
    private var cacheKey: String { "\(settings.config.level):\(paragraph)" }
    private var entries: [VocabularyEntry] { library.record(book, article.id).vocabulary[cacheKey] ?? [] }
    private var personal: [VocabularyEntry] {
        let text = article.paragraphs[paragraph].lowercased()
        return library.words.map(\.entry).filter { entry in
            text.range(of: #"(?<![\p{L}'])"# + NSRegularExpression.escapedPattern(for: entry.word.lowercased()) + #"(?![\p{L}'])"#,
                       options: .regularExpression) != nil && !entries.contains(where: { $0.id == entry.id })
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("第 \(paragraph + 1) 段 · \(settings.config.level)基线")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("含影响理解的习语、搭配与熟词僻义。点击 ＋ 加入个人生词本。")
                    .font(.caption).foregroundStyle(.secondary)
                JobProgressView(job: job)
                if entries.isEmpty && !job.running {
                    Text("暂无词条，可以生成或重新生成。").foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(entries) { entry in VocabularyCard(entry: entry, source: article.title) }
                if !personal.isEmpty {
                    Text("个人生词本中的词").font(.headline).padding(.top)
                    ForEach(personal) { entry in VocabularyCard(entry: entry, source: article.title) }
                }
                Button(entries.isEmpty ? "生成本段生词与短语" : "重新生成") { generate() }
                    .buttonStyle(.borderedProminent).disabled(job.running)
            }.padding(20)
        }
        .background(Color.paper).navigationTitle("生词与短语").navigationBarTitleDisplayMode(.inline)
        .task {
            if library.record(book, article.id).vocabulary[cacheKey] == nil { generate() }
        }
        .onDisappear { job.cancel() }
    }
    private func generate() {
        let key = cacheKey
        job.run(config: settings.config, messages: [ChatMessage(role: "user", content: Prompts.vocab(article.paragraphs[paragraph].prefixText(10000), level: settings.config.level))], tokens: 4500) { result in
            let words = try Prompts.decodeVocabulary(result)
            library.update(book, article.id) { $0.vocabulary[key] = words }
        }
    }
}

struct VocabularyCard: View {
    let entry: VocabularyEntry
    let source: String
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.word).font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                    if !entry.phonetic.isEmpty { Text(entry.phonetic).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                if entry.isPhrase { Text("短语").font(.caption).padding(5).background(.orange.opacity(0.12), in: Capsule()) }
                Button { library.add(entry, source: source) } label: {
                    Image(systemName: library.contains(entry) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                }.accessibilityLabel(library.contains(entry) ? "已加入生词本" : "加入生词本")
            }
            Text(entry.meaning).font(.body)
            if !entry.context.isEmpty { Text(entry.context).font(.subheadline).italic().foregroundStyle(.secondary) }
            if !entry.root.isEmpty { Text("词根与词源 · \(entry.root)").font(.caption).foregroundStyle(.secondary) }
        }
        .textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

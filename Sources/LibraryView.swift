import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importing = false
    private var recent: [Publication] {
        library.books.filter { $0.lastRead != nil }.sorted { $0.lastRead! > $1.lastRead! }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("让每一篇英文，都读有所获。")
                            .font(.title2.weight(.semibold)).foregroundStyle(Color.ink)
                        Text("原版阅读 · 语境词汇 · AI 答疑")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                    if !recent.isEmpty {
                        HStack {
                            Text("继续阅读").font(.headline)
                            Spacer()
                            NavigationLink("更多") { RecentReadingView() }.font(.subheadline)
                        }
                        ForEach(Array(recent.prefix(3))) { book in
                            NavigationLink { BookDestination(book: book, resume: true) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(book.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Text(book.format == "pdf" ? "第 \(book.page + 1) 页" : "上次读到第 \(book.articleID + 1) 篇 · 第 \(book.paragraphID + 1) 段")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Text("我的刊物").font(.headline)
                        Spacer()
                        Text("\(library.books.count) 本").font(.caption).foregroundStyle(.secondary)
                    }
                    if library.books.isEmpty {
                        ContentUnavailableView("带上你的第一本刊物", systemImage: "book.closed",
                                               description: Text("点击右上角 +，从“文件”导入 EPUB 或 PDF。"))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                        ForEach(library.books) { book in
                            NavigationLink { BookDestination(book: book) } label: { BookCard(book: book) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("删除刊物", role: .destructive) { library.delete(book) } }
                        }
                    }
                }.padding(20)
            }
            .background(Color.paper)
            .navigationTitle("刊读")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if library.importing { ProgressView() }
                    else { Button { importing = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("导入刊物") }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.pdf, UTType(filenameExtension: "epub") ?? .data]) { result in
                switch result {
                case .success(let url): Task { await library.importBook(url) }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
        }
    }
}

struct BookCard: View {
    let book: Publication
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.ink.gradient)
                if book.hasCover {
                    CoverImage(url: library.cover(book))
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed").font(.system(size: 36))
                        Text(book.title).font(.headline).multilineTextAlignment(.center).lineLimit(4)
                    }.padding(20).foregroundStyle(.white)
                }
            }
            .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.09), radius: 8, y: 4)
            Text(book.title).font(.subheadline.weight(.medium)).lineLimit(2).frame(height: 40, alignment: .top)
            Text(book.format.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
    }
}

struct CoverImage: View {
    let url: URL
    @State private var cover: UIImage?
    var body: some View {
        Group {
            if let cover { Image(uiImage: cover).resizable().scaledToFit() }
            else { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.white) }
        }
        .task(id: url) {
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            if let data { cover = UIImage(data: data) }
        }
    }
}

struct RecentEntry: Identifiable {
    let book: Publication
    let article: Int
    let record: ArticleRecord
    var id: String { "\(book.id):\(article)" }
}

struct RecentReadingView: View {
    @EnvironmentObject private var library: LibraryStore
    private var entries: [RecentEntry] {
        library.books.flatMap { book in
            library.records.filter { $0.key.hasPrefix(book.id.uuidString + ":") && $0.value.lastRead != nil }
                .map { RecentEntry(book: book, article: Int($0.key.split(separator: ":").last ?? "0") ?? 0, record: $0.value) }
        }.sorted { $0.record.lastRead! > $1.record.lastRead! }
    }
    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    BookDestination(book: entry.book, resume: true, targetArticle: entry.article)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.book.title).font(.headline)
                        Text(entry.book.format == "pdf" ? "PDF · 第 \(entry.book.page + 1) 页" : "第 \(entry.article + 1) 篇 · 第 \(entry.record.paragraph + 1) 段")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let date = entry.record.lastRead { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }
            }
        }.navigationTitle("最近阅读")
    }
}

struct BookDestination: View {
    let book: Publication
    var resume = false
    var targetArticle: Int?
    @EnvironmentObject private var library: LibraryStore
    @State private var articles: [Article]?
    @State private var failure: String?
    var body: some View {
        Group {
            if book.format == "pdf" { PDFReaderView(book: book) }
            else if let articles {
                if resume, let article = articles.first(where: { $0.id == (targetArticle ?? library.current(book).articleID) }) {
                    ArticleReaderView(book: book, article: article)
                } else { ArticleListView(book: book, articles: articles) }
            } else if let failure { ContentUnavailableView("读取失败", systemImage: "exclamationmark.triangle", description: Text(failure)) }
            else { ProgressView("读取目录…") }
        }
        .task(id: book.id) {
            guard book.format == "epub", articles == nil else { return }
            do { articles = try await library.articles(book) }
            catch { failure = error.localizedDescription }
        }
    }
}

struct ArticleListView: View {
    let book: Publication
    let articles: [Article]
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var job = GenerationJob()
    @State private var filter = "全部"
    var body: some View {
        VStack(spacing: 0) {
            Picker("筛选", selection: $filter) {
                Text("全部").tag("全部")
                ForEach(ReadingStatus.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented).padding()
            JobProgressView(job: job).padding(.horizontal)
            List {
                ForEach(articles.filter { filter == "全部" || library.record(book, $0.id).status.rawValue == filter }) { article in
                    let record = library.record(book, article.id)
                    NavigationLink { ArticleReaderView(book: book, article: article) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(article.id + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text("\(article.wordCount) 词").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if record.status != .unread { Text(record.status.rawValue).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(article.title).font(.headline)
                            if !record.summary.isEmpty { Text(record.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(5) }
                        }.padding(.vertical, 8)
                    }
                    .swipeActions {
                        Button("已读") { library.update(book, article.id) { $0.status = .read } }.tint(.green)
                        Button("忽略") { library.update(book, article.id) { $0.status = .ignored } }.tint(.gray)
                    }
                    .contextMenu {
                        ForEach(ReadingStatus.allCases, id: \.rawValue) { status in
                            Button(status.rawValue) { library.update(book, article.id) { $0.status = status } }
                        }
                        Button(record.summary.isEmpty ? "生成摘要" : "重新生成摘要") { summarize(article) }.disabled(job.running)
                    }
                }
            }.listStyle(.plain)
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .onDisappear { job.cancel() }
    }
    private func summarize(_ article: Article) {
        job.run(config: settings.config, messages: [ChatMessage(role: "user", content:
            "请给这篇文章写中文标题和 100–150 字中文摘要，不要额外说明。标题：\(article.title)\n正文（最多前 12000 字符）：\(article.paragraphs.joined(separator: "\n").prefixText(12000))")], tokens: 700) { result in
            library.update(book, article.id) { $0.summary = result }
        }
    }
}

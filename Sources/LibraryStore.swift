import Foundation
import SwiftUI
import Security

enum Disk {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagRead", isDirectory: true)
    }
    static func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

actor BookImporter {
    func run(_ source: URL) throws -> Publication {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["epub", "pdf"].contains(ext) else { throw ReaderError.message("仅支持 EPUB 和 PDF 文件。") }
        let id = UUID()
        let folder = Disk.folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let destination = folder.appendingPathComponent("book.\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            let result = try ext == "epub" ? BookParser.parseEPUB(destination) : BookParser.parsePDF(destination)
            try Disk.write(result.articles, to: folder.appendingPathComponent("articles.json"))
            if let cover = result.cover { try cover.write(to: folder.appendingPathComponent("cover.jpg"), options: .atomic) }
            return Publication(id: id, title: result.title, fileName: source.lastPathComponent,
                               format: ext, importedAt: Date(), hasCover: result.cover != nil)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Publication] = []
    @Published private(set) var records: [String: ArticleRecord] = [:]
    @Published private(set) var words: [SavedWord] = []
    @Published var error: String?
    @Published var importing = false
    private let importer = BookImporter()
    private var pendingSave: Task<Void, Never>?

    init() {
        do {
            try FileManager.default.createDirectory(at: Disk.root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: Disk.root.appendingPathComponent("library.json").path) {
                books = try Disk.read([Publication].self, from: Disk.root.appendingPathComponent("library.json"))
            }
            if FileManager.default.fileExists(atPath: Disk.root.appendingPathComponent("records.json").path) {
                records = try Disk.read([String: ArticleRecord].self, from: Disk.root.appendingPathComponent("records.json"))
            }
            if FileManager.default.fileExists(atPath: Disk.root.appendingPathComponent("words.json").path) {
                words = try Disk.read([SavedWord].self, from: Disk.root.appendingPathComponent("words.json"))
            }
        } catch { self.error = "读取本地数据失败：\(error.localizedDescription)" }
    }

    func importBook(_ url: URL) async {
        importing = true
        defer { importing = false }
        do { books.insert(try await importer.run(url), at: 0); save() }
        catch { self.error = error.localizedDescription }
    }

    func articles(_ book: Publication) async throws -> [Article] {
        let url = Disk.folder(book.id).appendingPathComponent("articles.json")
        return try await Task.detached(priority: .userInitiated) { try Disk.read([Article].self, from: url) }.value
    }

    func file(_ book: Publication) -> URL { Disk.folder(book.id).appendingPathComponent("book.\(book.format)") }
    func cover(_ book: Publication) -> URL { Disk.folder(book.id).appendingPathComponent("cover.jpg") }
    func current(_ book: Publication) -> Publication { books.first { $0.id == book.id } ?? book }
    func key(_ book: Publication, _ article: Int) -> String { "\(book.id.uuidString):\(article)" }
    func record(_ book: Publication, _ article: Int) -> ArticleRecord { records[key(book, article)] ?? ArticleRecord() }

    func update(_ book: Publication, _ article: Int, change: (inout ArticleRecord) -> Void) {
        let id = key(book, article)
        var value = records[id] ?? ArticleRecord()
        change(&value)
        records[id] = value
        save()
    }

    func progress(_ book: Publication, article: Int = 0, paragraph: Int? = nil, page: Int? = nil) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastRead = Date()
        books[index].articleID = article
        if let paragraph { books[index].paragraphID = paragraph }
        if let page { books[index].page = page }
        let id = key(book, article)
        var value = records[id] ?? ArticleRecord()
        value.lastRead = Date()
        if let paragraph { value.paragraph = paragraph }
        records[id] = value
        save()
    }

    func contains(_ entry: VocabularyEntry) -> Bool { words.contains { $0.entry.id == entry.id } }
    func add(_ entry: VocabularyEntry, source: String) {
        if let index = words.firstIndex(where: { $0.entry.id == entry.id }) { words[index].entry = entry }
        else { words.insert(SavedWord(entry: entry, source: source), at: 0) }
        save()
    }
    func removeWord(_ id: UUID) { words.removeAll { $0.id == id }; save() }

    func delete(_ book: Publication) {
        do { try FileManager.default.removeItem(at: Disk.folder(book.id)) }
        catch { self.error = error.localizedDescription; return }
        books.removeAll { $0.id == book.id }
        records = records.filter { !$0.key.hasPrefix(book.id.uuidString + ":") }
        save()
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flush()
        }
    }
    func flush() {
        pendingSave?.cancel()
        do {
            try Disk.write(books, to: Disk.root.appendingPathComponent("library.json"))
            try Disk.write(records, to: Disk.root.appendingPathComponent("records.json"))
            try Disk.write(words, to: Disk.root.appendingPathComponent("words.json"))
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
}

enum Keychain {
    private static let service = "com.haithink.magread.llm"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        if key.isEmpty { SecItemDelete(query as CFDictionary); return }
        let value: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(value) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ReaderError.message("无法保存密钥到钥匙串（\(status)）。") }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var config: LLMConfiguration
    @AppStorage("readerFontSize") var fontSize = 19.0
    init() {
        config = UserDefaults.standard.data(forKey: "llmConfiguration")
            .flatMap { try? JSONDecoder().decode(LLMConfiguration.self, from: $0) } ?? LLMConfiguration()
        config.apiKey = Keychain.read()
    }
    func save(_ value: LLMConfiguration) throws {
        _ = try value.endpoint()
        try Keychain.write(value.apiKey.trimmed)
        let encoded = try JSONEncoder().encode(value)
        UserDefaults.standard.set(encoded, forKey: "llmConfiguration")
        config = value
    }
}

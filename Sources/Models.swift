import Foundation

struct Article: Codable, Identifiable, Equatable {
    var id: Int
    var title: String
    var paragraphs: [String]
    var wordCount: Int { paragraphs.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count } }
}

struct Publication: Codable, Identifiable {
    var id: UUID
    var title: String
    var fileName: String
    var format: String
    var importedAt: Date
    var lastRead: Date?
    var articleID: Int = 0
    var paragraphID: Int = 0
    var page: Int = 0
    var hasCover: Bool = false
}

enum ReadingStatus: String, Codable, CaseIterable {
    case unread = "未读", read = "已读", ignored = "不感兴趣"
}

struct ArticleRecord: Codable {
    var summary = ""
    var status: ReadingStatus = .unread
    var paragraph = 0
    var lastRead: Date?
    var vocabulary: [String: [VocabularyEntry]] = [:]
    var discussions: [String: [ChatMessage]] = [:]
}

struct VocabularyEntry: Codable, Identifiable, Equatable {
    var word: String
    var phonetic: String
    var meaning: String
    var context: String
    var root: String
    var isPhrase: Bool
    var id: String { word.lowercased() }
}

struct SavedWord: Codable, Identifiable {
    var id: UUID = UUID()
    var entry: VocabularyEntry
    var source: String
    var createdAt: Date = Date()
}

struct ChatMessage: Codable, Identifiable {
    var id: UUID = UUID()
    var role: String
    var content: String
}

enum Provider: String, Codable, CaseIterable {
    case openAI = "OpenAI 兼容", anthropic = "Anthropic"
}

struct LLMConfiguration: Codable {
    var provider: Provider = .openAI
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-chat"
    var apiKey = ""
    var level = "四级"

    enum CodingKeys: String, CodingKey { case provider, baseURL, model, level }

    func endpoint() throws -> URL {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ReaderError.message("请输入 HTTPS API 地址，不要在地址中填写密钥、查询参数或密码。")
        }
        let suffix = provider == .anthropic ? "/messages" : "/chat/completions"
        if base.hasSuffix(suffix) { return url }
        let versioned = base.range(of: #"/v\d+$"#, options: .regularExpression) != nil
        guard let endpoint = URL(string: base + (versioned ? "" : "/v1") + suffix) else {
            throw ReaderError.message("API 地址无效。")
        }
        return endpoint
    }
}

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func prefixText(_ count: Int) -> String { String(prefix(count)) }
}

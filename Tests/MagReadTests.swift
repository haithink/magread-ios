import XCTest
import ZIPFoundation
@testable import MagRead

final class MagReadTests: XCTestCase {
    func testAppBundlesThirdPartyNotices() {
        let appBundle = Bundle(for: LibraryStore.self)
        XCTAssertNotNil(appBundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
    }

    func testEndpoints() throws {
        var config = LLMConfiguration()
        XCTAssertEqual(try config.endpoint().absoluteString, "https://api.deepseek.com/v1/chat/completions")
        config.baseURL = "https://gateway.example/v3/"
        XCTAssertEqual(try config.endpoint().absoluteString, "https://gateway.example/v3/chat/completions")
        config.baseURL = "https://gateway.example/v1/chat/completions"
        XCTAssertEqual(try config.endpoint().absoluteString, config.baseURL)
        config.provider = .anthropic
        config.baseURL = "https://api.anthropic.com"
        XCTAssertEqual(try config.endpoint().absoluteString, "https://api.anthropic.com/v1/messages")
        config.baseURL = "http://example.com"
        XCTAssertThrowsError(try config.endpoint())
        config.baseURL = "https://secret:password@example.com/v1"
        XCTAssertThrowsError(try config.endpoint())
    }

    func testDeepSeekRequestDisablesThinkingAndStreams() throws {
        var config = LLMConfiguration()
        config.apiKey = "synthetic-test-key"
        let request = try LLMClient.request(config: config, system: "test", messages: [ChatMessage(role: "user", content: "hello")], tokens: 100)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
    }

    func testKeyIsNeverEncodedWithSettings() throws {
        var config = LLMConfiguration()
        config.apiKey = "DO-NOT-PERSIST-THIS-TEST-SECRET"
        let data = try JSONEncoder().encode(config)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(config.apiKey))
        let decoded = try JSONDecoder().decode(LLMConfiguration.self, from: data)
        XCTAssertEqual(decoded.apiKey, "")
        XCTAssertEqual(decoded.model, config.model)
    }

    func testOpenAIStreamingReasoningAndNullAreHandled() throws {
        var stream = StreamAccumulator()
        try stream.consume(#"{"choices":[{"delta":{"reasoning_content":"thinking"},"finish_reason":null}]}"#, provider: .openAI)
        XCTAssertEqual(stream.progress.phase, "模型正在思考")
        try stream.consume(#"{"choices":[{"delta":{"content":"Hello","reasoning_content":null},"finish_reason":null}]}"#, provider: .openAI)
        try stream.consume(#"{"choices":[{"delta":{"content":" world"},"finish_reason":"stop"}]}"#, provider: .openAI)
        XCTAssertEqual(try stream.result(), "Hello world")
    }

    func testNormalJSONResponseIsConsumedWithoutRetry() throws {
        var stream = StreamAccumulator()
        try stream.consume(#"{"choices":[{"message":{"content":"one answer","reasoning_content":null},"finish_reason":"stop"}]}"#, provider: .openAI)
        XCTAssertEqual(try stream.result(), "one answer")
    }

    func testTruncationAndBrokenStreamAreRejected() throws {
        var stream = StreamAccumulator()
        try stream.consume(#"{"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#, provider: .openAI)
        XCTAssertThrowsError(try stream.result())
        stream = StreamAccumulator()
        try stream.consume(#"{"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#, provider: .openAI)
        XCTAssertThrowsError(try stream.result())
    }

    func testAnthropicStreamingAndNormalResponse() throws {
        var stream = StreamAccumulator()
        try stream.consume(#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}"#, provider: .anthropic)
        try stream.consume(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, provider: .anthropic)
        try stream.consume(#"{"type":"message_stop"}"#, provider: .anthropic)
        XCTAssertEqual(try stream.result(), "你好")
        stream = StreamAccumulator()
        try stream.consume(#"{"content":[{"type":"text","text":"完整回答"}],"stop_reason":"end_turn"}"#, provider: .anthropic)
        XCTAssertEqual(try stream.result(), "完整回答")
    }

    func testVocabularyDecoding() throws {
        let response = """
        ```json
        [{"word":"chart his own path","phonetic":"","meaning":"走自己的路","context":"chart his own path","root":"","isPhrase":true}]
        ```
        """
        let entries = try Prompts.decodeVocabulary(response)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isPhrase)
        XCTAssertThrowsError(try Prompts.decodeVocabulary("not json"))
    }

    func testEPUBPathValidation() throws {
        XCTAssertEqual(try BookParser.resolve("../Text/story%20one.xhtml#p1", relativeTo: "OPS/Package"), "OPS/Text/story one.xhtml")
        XCTAssertThrowsError(try BookParser.resolve("../../../outside", relativeTo: "OPS"))
        XCTAssertThrowsError(try BookParser.resolve("https://example.com/tracker", relativeTo: "OPS"))
        XCTAssertThrowsError(try BookParser.resolve("/absolute/path", relativeTo: "OPS"))
    }

    func testEPUBUsesSpineOrderAndSeparateArticles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        let files: [String: String] = [
            "META-INF/container.xml": #"<?xml version="1.0"?><container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>"#,
            "OPS/book.opf": #"<?xml version="1.0"?><package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Sample Journal</dc:title></metadata><manifest><item id="second" href="second.xhtml"/><item id="first" href="first.xhtml"/></manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>"#,
            "OPS/first.xhtml": "<html><body><h1>First article</h1><p>We chart our own path.</p><blockquote><p>A quotation.</p></blockquote></body></html>",
            "OPS/second.xhtml": "<html><body><h1>Second article</h1><p>A candid conversation.</p></body></html>"
        ]
        for (path, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in
                data.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        let book = try BookParser.parseEPUB(url)
        XCTAssertEqual(book.title, "Sample Journal")
        XCTAssertEqual(book.articles.count, 2)
        XCTAssertEqual(book.articles[0].title, "First article")
        XCTAssertEqual(book.articles[1].title, "Second article")
        XCTAssertEqual(book.articles[0].paragraphs.filter { $0 == "A quotation." }.count, 1)
    }
}

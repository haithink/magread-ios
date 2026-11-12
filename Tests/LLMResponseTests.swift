import XCTest
@testable import MagRead

private enum ResponseFixtures {
    static let anthropic = """
    : keep-alive

    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","content_block":{"type":"text","text":"连接"}}

    event: ping
    data: {"type":"ping"}

    event: content_block_delta
    data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"成功"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

    event: message_stop
    data: {"type":"message_stop"}


    """
    static let openAI = """
    data: {"choices":[{"delta":{"reasoning_content":"thinking"},"finish_reason":null}]}

    data: {"choices":[{"delta":{"content":"连接","reasoning_content":null},"finish_reason":null}]}

    data: {"choices":[{"delta":{"content":"成功"},"finish_reason":"stop"}]}

    data: [DONE]


    """
    static let json = #"{"content":[{"type":"text","text":"连接成功"}],"stop_reason":"end_turn"}"#
}

private final class ModelStubProtocol: URLProtocol {
    private var delayed: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url?.pathComponents.dropFirst().first ?? ""
        let content: String
        let type: String
        var status = 200
        switch name {
        case "anthropic": content = ResponseFixtures.anthropic; type = "text/event-stream"
        case "openai": content = ResponseFixtures.openAI; type = "text/event-stream"
        case "sse-wrong-header": content = ResponseFixtures.anthropic; type = "application/json"
        case "json-wrong-header": content = ResponseFixtures.json; type = "text/event-stream"
        case "json": content = ResponseFixtures.json; type = "application/json"
        case "malformed": content = "data: {broken JSON}\n\n"; type = "text/event-stream"
        case "error": content = "data: {\"error\":{\"message\":\"synthetic-test-key failed\"}}\n\n"; type = "text/event-stream"
        case "truncated": content = "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"; type = "text/event-stream"
        case "broken": content = "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"partial\"}}\n\n"; type = "text/event-stream"
        case "http-error": status = 401; content = "synthetic-test-key rejected"; type = "application/json"
        case "wait":
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            }
            delayed = item
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: item)
            return
        default: content = "<html>Gateway page</html>"; type = "text/html"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Split arbitrarily, including in the middle of UTF-8 characters and SSE delimiters.
        let bytes = Array(content.utf8)
        for offset in stride(from: 0, to: bytes.count, by: 7) {
            client?.urlProtocol(self, didLoad: Data(bytes[offset..<min(offset + 7, bytes.count)]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { delayed?.cancel() }
}

final class LLMResponseTests: XCTestCase {
    private func configuration(_ path: String, provider: Provider = .anthropic) -> LLMConfiguration {
        var config = LLMConfiguration()
        config.provider = provider
        config.baseURL = "https://stub.example/\(path)"
        config.model = "synthetic-model"
        config.apiKey = "synthetic-test-key"
        return config
    }
    private func receive(_ path: String, provider: Provider = .anthropic) async throws -> String {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ModelStubProtocol.self]
        return try await LLMClient.shared.chat(config: configuration(path, provider: provider), system: "test",
            messages: [ChatMessage(role: "user", content: "test")], sessionConfiguration: session) { _ in }
    }

    func testDeepSeekAnthropicRequestMatchesAndroidAndUsesFullEndpoint() throws {
        var config = LLMConfiguration()
        config.provider = .anthropic
        config.baseURL = "https://api.deepseek.com/anthropic"
        config.model = "deepseek-v4-flash"
        config.apiKey = "synthetic-test-key"
        let request = try LLMClient.request(config: config, system: "test", messages: [ChatMessage(role: "user", content: "test")], tokens: LLMClient.connectionTestTokens)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "synthetic-test-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual(body["max_tokens"] as? Int, 2000)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
    }

    func testAnthropicSSEThroughRealURLSessionByteSequence() async throws {
        let answer = try await receive("anthropic")
        XCTAssertEqual(answer, "连接成功")
    }

    func testOpenAISSEThroughRealURLSessionByteSequence() async throws {
        let answer = try await receive("openai", provider: .openAI)
        XCTAssertEqual(answer, "连接成功")
    }

    func testSSEWithJSONContentType() async throws {
        let answer = try await receive("sse-wrong-header")
        XCTAssertEqual(answer, "连接成功")
    }

    func testNormalJSONWithEventStreamContentType() async throws {
        let answer = try await receive("json-wrong-header")
        XCTAssertEqual(answer, "连接成功")
    }

    func testNormalJSONThroughURLSession() async throws {
        let answer = try await receive("json")
        XCTAssertEqual(answer, "连接成功")
    }

    func testMalformedResponseExplainsItIsNotTheConfiguration() async {
        do { _ = try await receive("malformed"); XCTFail("Malformed response must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("并非粘贴的配置 JSON")) }
    }

    func testResponseAndHTTPErrorDoNotExposeKey() async {
        for fixture in ["error", "http-error"] {
            do { _ = try await receive(fixture); XCTFail("Error must propagate") }
            catch { XCTAssertFalse(error.localizedDescription.contains("synthetic-test-key")) }
        }
    }

    func testTruncatedAndInterruptedStreamsAreRejected() async {
        for fixture in ["truncated", "broken"] {
            do { _ = try await receive(fixture); XCTFail("Incomplete response must fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains(fixture == "truncated" ? "输出上限" : "连接提前结束")) }
        }
    }

    func testCancellationWhileWaitingDoesNotWaitForTimeout() async {
        let task = Task { try await self.receive("wait") }
        try? await Task.sleep(for: .milliseconds(100))
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testDecoderPreservesLFCRLFAndCREventBoundaries() throws {
        for separator in ["\n", "\r\n", "\r"] {
            let input = ResponseFixtures.anthropic.replacingOccurrences(of: "\n", with: separator)
            var decoder = LLMResponseDecoder()
            var state = StreamAccumulator()
            for byte in input.utf8 {
                if let packet = try decoder.consume(byte) { try state.consume(packet, provider: .anthropic) }
            }
            for packet in try decoder.finish() { try state.consume(packet, provider: .anthropic) }
            XCTAssertEqual(try state.result(), "连接成功")
        }
    }

    func testDecoderSupportsMultilineDataAndLastEventWithoutBlankLine() throws {
        let input = "\u{feff}: comment\n\nevent: message\ndata: {\"type\":\"content_block_delta\",\ndata: \"delta\":{\"text\":\"中文\"}}\n\ndata: {\"type\":\"message_stop\"}"
        var decoder = LLMResponseDecoder()
        var state = StreamAccumulator()
        for byte in input.utf8 {
            if let packet = try decoder.consume(byte) { try state.consume(packet, provider: .anthropic) }
        }
        for packet in try decoder.finish() { try state.consume(packet, provider: .anthropic) }
        XCTAssertEqual(try state.result(), "中文")
    }

    func testDecoderSupportsJSONWithBOMWhitespaceAndNewlines() throws {
        for input in [" \n\n" + ResponseFixtures.json, "\u{feff}" + ResponseFixtures.json, "\u{feff}\n" + ResponseFixtures.json] {
            var decoder = LLMResponseDecoder()
            for byte in input.utf8 { XCTAssertNil(try decoder.consume(byte)) }
            var state = StreamAccumulator()
            for packet in try decoder.finish() { try state.consume(packet, provider: .anthropic) }
            XCTAssertEqual(try state.result(), "连接成功")
        }
    }

    func testNetworkParseErrorHasSpecificExplanation() {
        let message = LLMFailure.message(URLError(.cannotParseResponse), secret: "synthetic-key")
        XCTAssertTrue(message.contains("HTTP 响应"))
        XCTAssertFalse(message.contains("synthetic-key"))
    }
}

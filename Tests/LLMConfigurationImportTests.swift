import XCTest
@testable import MagRead

final class LLMConfigurationImportTests: XCTestCase {
    func testCCSwitchEnvironmentAndDefaultModelFallback() throws {
        let text = #"{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example/anthropic","ANTHROPIC_AUTH_TOKEN":"synthetic-token","ANTHROPIC_DEFAULT_SONNET_MODEL":"test-sonnet"}}"#
        let config = try LLMConfigurationImport.parse(text, level: "六级")
        XCTAssertEqual(config.provider, .anthropic)
        XCTAssertEqual(config.baseURL, "https://gateway.example/anthropic")
        XCTAssertEqual(config.apiKey, "synthetic-token")
        XCTAssertEqual(config.model, "test-sonnet")
        XCTAssertEqual(config.level, "六级")
    }

    func testWrappedProviderAndAnthropicAPIKey() throws {
        let text = #"{"name":"Test provider","apiFormat":"anthropic","settingsConfig":{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example","ANTHROPIC_API_KEY":"synthetic-key","ANTHROPIC_MODEL":"test-main","ANTHROPIC_DEFAULT_SONNET_MODEL":"test-fallback"}}}"#
        let config = try LLMConfigurationImport.parse(text, level: "四级")
        XCTAssertEqual(config.provider, .anthropic)
        XCTAssertEqual(config.apiKey, "synthetic-key")
        XCTAssertEqual(config.model, "test-main")
    }

    func testStringifiedSettingsConfig() throws {
        let inner = #"{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example","ANTHROPIC_AUTH_TOKEN":"synthetic-token","ANTHROPIC_MODEL":"test-model"}}"#
        let outer = String(decoding: try JSONSerialization.data(withJSONObject: ["settingsConfig": inner]), as: UTF8.self)
        let config = try LLMConfigurationImport.parse(outer, level: "四级")
        XCTAssertEqual(config.model, "test-model")
        XCTAssertEqual(config.apiKey, "synthetic-token")
    }

    func testFlatOpenAIAndMarkdownFence() throws {
        let config = try LLMConfigurationImport.parse("""
        ```json
        {"baseUrl":"https://gateway.example/v1", "apiKey":"synthetic-key", "model":"test-model"}
        ```
        """, level: "四级")
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.baseURL, "https://gateway.example/v1")
        XCTAssertEqual(config.apiKey, "synthetic-key")
        XCTAssertEqual(config.model, "test-model")
    }

    func testOpenAIEnvironmentAndSnakeCaseAliases() throws {
        let config = try LLMConfigurationImport.parse(#"{"env":{"OPENAI_BASE_URL":"https://gateway.example","OPENAI_API_KEY":"synthetic-key","OPENAI_MODEL":"test-model"}}"#, level: "四级")
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.model, "test-model")
        XCTAssertEqual(config.apiKey, "synthetic-key")
        let flat = try LLMConfigurationImport.parse(#"{"base_url":"https://gateway.example","api_key":"synthetic-key","model_name":"test-model"}"#, level: "四级")
        XCTAssertEqual(flat.baseURL, config.baseURL)
        XCTAssertEqual(flat.model, config.model)
    }

    func testMissingFieldsStayEmptyForPreviewInsteadOfReusingOldDefaults() throws {
        let config = try LLMConfigurationImport.parse(#"{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example","ANTHROPIC_AUTH_TOKEN":"synthetic-token"}}"#, level: "四级")
        XCTAssertEqual(config.model, "")
        let modelOnly = try LLMConfigurationImport.parse(#"{"model":"test-model"}"#, level: "四级")
        XCTAssertEqual(modelOnly.apiKey, "")
        XCTAssertEqual(modelOnly.baseURL, "")
    }

    func testExplicitProviderUsesMatchingEnvironmentCredentials() throws {
        let config = try LLMConfigurationImport.parse(#"{"provider":"openai","env":{"ANTHROPIC_BASE_URL":"https://anthropic.example","ANTHROPIC_AUTH_TOKEN":"anthropic-test-key","OPENAI_BASE_URL":"https://openai.example","OPENAI_API_KEY":"openai-test-key"}}"#, level: "四级")
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.apiKey, "openai-test-key")
        XCTAssertEqual(config.baseURL, "https://openai.example")
    }

    func testAmbiguousProvidersAreRejected() {
        XCTAssertThrowsError(try LLMConfigurationImport.parse(#"{"env":{"ANTHROPIC_AUTH_TOKEN":"a","OPENAI_API_KEY":"b"}}"#, level: "四级"))
        XCTAssertThrowsError(try LLMConfigurationImport.parse(#"{"providers":{"first":{"apiKey":"a"},"second":{"apiKey":"b"}}}"#, level: "四级"))
    }

    func testInvalidInputErrorsNeverEchoSecrets() {
        for text in ["not json synthetic-secret", "[]", #"{"apiKey":"synthetic-secret""#, "{}", String(repeating: "x", count: 270000)] {
            do { _ = try LLMConfigurationImport.parse(text, level: "四级"); XCTFail("Invalid JSON must fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("synthetic-secret")) }
        }
    }

    func testImportedConfigurationStillExcludesSecretFromEncodedSettings() throws {
        let config = try LLMConfigurationImport.parse(#"{"baseURL":"https://gateway.example","apiKey":"synthetic-secret","model":"test-model"}"#, level: "四级")
        let encoded = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-secret"))
        XCTAssertFalse(encoded.contains("apiKey"))
    }
}

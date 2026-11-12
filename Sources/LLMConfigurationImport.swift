import Foundation

enum LLMConfigurationImport {
    static func parse(_ input: String, level: String) throws -> LLMConfiguration {
        var text = input.trimmed
        guard text.utf8.count <= 256 * 1024 else { throw ReaderError.message("配置过大，请只粘贴单个模型服务的 JSON。") }
        if text.hasPrefix("```"), let newline = text.firstIndex(of: "\n"), text.hasSuffix("```") {
            text = String(text[text.index(after: newline)..<text.index(text.endIndex, offsetBy: -3)]).trimmed
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let root = object as? [String: Any] else {
            throw ReaderError.message("无法识别 JSON，请粘贴完整配置对象，检查引号和逗号。")
        }
        // Read one provider only. Never combine credentials from different provider objects.
        var fields = root
        for name in ["settingsConfig", "settings", "config"] {
            if let nested = root[name] as? [String: Any] { fields = nested; break }
            if let nested = root[name] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(nested.utf8)) as? [String: Any] {
                fields = parsed; break
            }
        }
        let environment = fields["env"] as? [String: Any] ?? [:]
        let authentication = fields["auth"] as? [String: Any] ?? [:]
        func value(_ names: [String], in source: [String: Any]) -> String? {
            for name in names {
                if let result = source[name] as? String, !result.trimmed.isEmpty { return result.trimmed }
            }
            return nil
        }
        let providerName = (value(["apiFormat", "provider", "protocol"], in: fields)
            ?? value(["apiFormat", "provider", "protocol"], in: root) ?? "").lowercased()
        let anthropicFields = ["ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL"]
        let openAIFields = ["OPENAI_BASE_URL", "OPENAI_API_BASE", "OPENAI_API_KEY", "OPENAI_MODEL"]
        let hasAnthropic = value(anthropicFields, in: environment) != nil || value(anthropicFields, in: fields) != nil
        let hasOpenAI = value(openAIFields, in: environment) != nil || value(openAIFields, in: fields) != nil
        let baseURL = value(["baseURL", "baseUrl", "base_url", "apiBase", "api_base", "url", "endpoint"], in: fields)
        let provider: Provider
        if ["anthropic", "claude", "claude-code"].contains(providerName) || providerName == Provider.anthropic.rawValue.lowercased() {
            provider = .anthropic
        } else if ["openai", "openai-compatible", "openai_compatible", "deepseek"].contains(providerName) || providerName == Provider.openAI.rawValue.lowercased() {
            provider = .openAI
        } else if hasAnthropic && hasOpenAI {
            throw ReaderError.message("JSON 同时包含两种模型服务，请只粘贴一个服务的配置，或指定 provider。")
        } else if hasAnthropic || baseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("/messages") == true {
            provider = .anthropic
        } else { provider = .openAI }

        let urlKeys = provider == .anthropic ? ["ANTHROPIC_BASE_URL"] : ["OPENAI_BASE_URL", "OPENAI_API_BASE"]
        let secretKeys = provider == .anthropic ? ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"] : ["OPENAI_API_KEY"]
        let modelKeys = provider == .anthropic
            ? ["ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL"]
            : ["OPENAI_MODEL", "OPENAI_DEFAULT_MODEL"]
        var result = LLMConfiguration()
        result.provider = provider
        result.level = level
        result.baseURL = baseURL ?? value(urlKeys, in: environment) ?? value(urlKeys, in: fields) ?? ""
        result.apiKey = value(["apiKey", "api_key", "API_KEY", "authToken", "auth_token", "token", "key"], in: fields)
            ?? value(secretKeys, in: environment) ?? value(secretKeys, in: fields) ?? value(secretKeys, in: authentication) ?? ""
        result.model = value(["model", "modelName", "model_name"], in: fields)
            ?? value(modelKeys, in: environment) ?? value(modelKeys, in: fields) ?? ""
        guard !result.baseURL.isEmpty || !result.apiKey.isEmpty || !result.model.isEmpty else {
            throw ReaderError.message("未找到 API 地址、密钥或模型名。支持单个 CC Switch 服务的 settingsConfig / env，以及 baseUrl、apiKey、model 格式。")
        }
        return result
    }
}

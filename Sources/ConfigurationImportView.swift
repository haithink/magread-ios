import SwiftUI

struct ConfigurationImportView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    let onSaved: (LLMConfiguration) -> Void
    @State private var json = ""
    @State private var parsed = LLMConfiguration()
    @State private var hasPreview = false
    @State private var error: String?

    var body: some View {
        Form {
            if !hasPreview {
                Section {
                    TextEditor(text: $json)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 180, maxHeight: 260)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive()
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { json = text; parse() }
                    }
                    Button("识别配置") { parse() }.disabled(json.trimmed.isEmpty)
                } header: { Text("粘贴完整 JSON") } footer: {
                    Text("支持 CC Switch 的 settingsConfig / env 配置，以及 baseUrl、apiKey、model 格式。仅在手机本地识别。")
                }
            } else {
                Section("已识别的模型服务") {
                    Picker("协议", selection: $parsed.provider) {
                        ForEach(Provider.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
                    }
                    TextField("API 地址（HTTPS）", text: $parsed.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("模型名称", text: $parsed.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key", text: $parsed.apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if parsed.baseURL.trimmed.isEmpty || parsed.model.trimmed.isEmpty || parsed.apiKey.trimmed.isEmpty {
                        Text("JSON 未包含完整信息，请补充空缺字段后保存。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("导入并保存") {
                        do {
                            try settings.save(parsed)
                            onSaved(settings.config)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(parsed.baseURL.trimmed.isEmpty || parsed.model.trimmed.isEmpty || parsed.apiKey.trimmed.isEmpty)
                    Button("重新粘贴") { hasPreview = false; parsed = LLMConfiguration(); error = nil }
                }
            }
            if let error { Section { Text(error).font(.callout).foregroundStyle(.red) } }
            Section {
                Text("识别后清空原始 JSON，API Key 仅保存到 iOS 钥匙串。导入不会自动测试连接或发送配置到服务器。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("JSON 导入").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }

    private func parse() {
        do {
            parsed = try LLMConfigurationImport.parse(json, level: settings.config.level)
            json = ""
            error = nil
            hasPreview = true
        } catch { self.error = error.localizedDescription }
    }
}

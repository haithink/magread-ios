import Foundation

/// Preserve SSE framing at the byte level. Foundation's text line adapters may
/// omit empty lines, which are the event delimiters in SSE.
struct LLMResponseDecoder {
    private enum Mode { case undecided, events, json }
    private var mode: Mode = .undecided
    private var line = Data()
    private var json = Data()
    private var event: [String] = []
    private var previousCR = false
    private var firstLine = true
    private var received = 0

    mutating func consume(_ byte: UInt8) throws -> String? {
        received += 1
        guard received <= 8 * 1024 * 1024 else { throw ReaderError.message("模型响应过大。") }
        if mode == .json {
            json.append(byte)
            return nil
        }
        if byte == 13 {
            previousCR = true
            return try consumeLine()
        }
        if byte == 10 {
            if previousCR { previousCR = false; return nil }
            return try consumeLine()
        }
        previousCR = false
        if mode == .undecided && (byte == 123 || byte == 91),
           line.allSatisfy({ $0 == 32 || $0 == 9 }) {
            mode = .json
            json = line
            line.removeAll(keepingCapacity: true)
            json.append(byte)
            return nil
        }
        line.append(byte)
        return nil
    }

    private mutating func consumeLine() throws -> String? {
        var value = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if firstLine {
            firstLine = false
            if value.hasPrefix("\u{feff}") { value.removeFirst() }
        }
        // Handles a JSON body preceded by a UTF-8 BOM as well.
        if mode == .undecided && (value.trimmed.hasPrefix("{") || value.trimmed.hasPrefix("[")) {
            mode = .json
            json = Data((value + "\n").utf8)
            return nil
        }
        if value.isEmpty {
            guard !event.isEmpty else { return nil }
            let packet = event.joined(separator: "\n")
            event.removeAll(keepingCapacity: true)
            return packet
        }
        if value.hasPrefix(":") { mode = .events; return nil }
        let field = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard ["data", "event", "id", "retry"].contains(String(field[0])) else {
            throw ReaderError.message("模型接口返回了无法识别的内容，可能是网页或网关提示；请检查 API 地址和网络。")
        }
        mode = .events
        if field[0] == "data" {
            var data = field.count == 2 ? String(field[1]) : ""
            if data.hasPrefix(" ") { data.removeFirst() }
            event.append(data)
        }
        return nil
    }

    mutating func finish() throws -> [String] {
        if mode == .json { return [String(decoding: json, as: UTF8.self)] }
        var packets: [String] = []
        if !line.isEmpty, let packet = try consumeLine() { packets.append(packet) }
        if mode == .json { return [String(decoding: json, as: UTF8.self)] }
        if !event.isEmpty {
            packets.append(event.joined(separator: "\n"))
            event.removeAll()
        }
        return packets
    }
}

enum LLMFailure {
    static func message(_ error: Error, secret: String) -> String {
        let text: String
        if let network = error as? URLError {
            switch network.code {
            case .timedOut: text = "连接模型服务超时，请稍后重试或检查网络。"
            case .cannotParseResponse, .badServerResponse, .cannotDecodeContentData, .cannotDecodeRawData:
                text = "无法解析模型服务的 HTTP 响应，请检查 API 地址、网络或代理。"
            default: text = "连接模型服务失败（网络错误 \(network.code.rawValue)），请检查网络及 API 地址。"
            }
        } else { text = error.localizedDescription }
        guard !secret.isEmpty else { return text }
        return text.replacingOccurrences(of: secret, with: "[密钥已隐藏]")
    }
}

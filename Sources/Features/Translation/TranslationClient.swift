import Foundation

// MARK: - 可读错误

enum TranslationError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case insecureURL
    case missingModel
    case unauthorized
    case notFound
    case rateLimited
    case server(Int)
    case http(Int, String)
    case timeout
    case badResponse
    case cancelled
    case network(String)
    case secretStore

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没有配置供应商，请先填写 Base URL、API Key 和模型。"
        case .invalidURL:
            return "Base URL 格式不正确，请填写完整地址，例如 https://api.openai.com/v1。"
        case .insecureURL:
            return "只允许 HTTPS。本地模型可以使用 http://localhost 或 http://127.0.0.1。"
        case .missingModel:
            return "请填写模型名称，例如 gpt-4o-mini。"
        case .unauthorized:
            return "API Key 无效或没有权限（401），请检查密钥。"
        case .notFound:
            return "接口地址不对（404），请检查 Base URL，通常需要以 /v1 结尾。"
        case .rateLimited:
            return "请求过于频繁或额度用尽（429），稍后再试或检查账户额度。"
        case .server(let status):
            return "供应商服务异常（\(status)），稍后再试。"
        case .http(let status, let message):
            return message.isEmpty
                ? "请求失败（\(status)）。"
                : "请求失败（\(status)）：\(message)"
        case .timeout:
            return "请求超时，请检查网络或供应商状态。"
        case .badResponse:
            return "返回格式无法解析。"
        case .cancelled:
            return "已取消。"
        case .network(let message):
            return message.isEmpty ? "网络请求失败。" : message
        case .secretStore:
            return "无法保存 API Key，请检查应用支持目录的读写权限。"
        }
    }
}

// MARK: - 地址归一化

/// 用户可能填 `.../v1`、`.../v1/`、`.../v1/chat/completions` 或裸域名。
/// 这里统一收成 base，再拼我们自己的端点，避免出现 `/v1/v1`。
enum TranslationEndpoint {

    static func normalizedBase(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        if text.hasSuffix("/chat/completions") {
            text.removeLast("/chat/completions".count)
        } else if text.hasSuffix("/models") {
            text.removeLast("/models".count)
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        let path = URL(string: text)?.path ?? ""
        let last = path.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        let isVersionSegment = last.count >= 2
            && last.first == "v"
            && last.dropFirst().allSatisfy(\.isNumber)

        return isVersionSegment ? text : text + "/v1"
    }

    static func chatURLString(_ raw: String) -> String? {
        normalizedBase(raw).map { $0 + "/chat/completions" }
    }

    static func modelsURLString(_ raw: String) -> String? {
        normalizedBase(raw).map { $0 + "/models" }
    }

    /// 返回 nil 表示安全；否则是可直接展示给用户的原因。
    static func insecureReason(_ raw: String) -> String? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }
        guard scheme == "http" else { return nil }
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
        return localHosts.contains(host)
            ? nil
            : "只允许 HTTPS。本地模型可以使用 http://localhost 或 http://127.0.0.1。"
    }
}

// MARK: - HTTP 错误映射

enum TranslationHTTPError {

    static func map(status: Int, body: String) -> TranslationError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        case 500...599:
            return .server(status)
        default:
            return .http(status, snippet(body))
        }
    }

    /// 只保留一小段可读文本，并抹掉可能被供应商回显的 key。
    static func snippet(_ body: String) -> String {
        var text = body
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_-]+"#,
            with: "sk-***",
            options: .regularExpression
        )
        if text.count > 160 {
            text = String(text.prefix(160)) + "…"
        }
        return text
    }
}

// MARK: - 词典结果

enum DictionaryLookup: Equatable {
    case entry(DictionaryEntry)
    case raw(String)
}

// MARK: - 客户端

final class TranslationClient {

    static let shared = TranslationClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: 模型列表

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        try Self.validate(baseURL: baseURL, apiKey: apiKey)
        guard let urlString = TranslationEndpoint.modelsURLString(baseURL),
              let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.badResponse
        }

        var ids: [String] = []
        if let items = object["data"] as? [Any] {
            for item in items {
                if let dict = item as? [String: Any], let id = dict["id"] as? String {
                    ids.append(id)
                } else if let id = item as? String {
                    ids.append(id)
                }
            }
        }
        if let items = object["models"] as? [Any] {
            for item in items {
                if let dict = item as? [String: Any], let id = dict["id"] as? String {
                    ids.append(id)
                } else if let id = item as? String {
                    ids.append(id)
                }
            }
        }

        return Array(Set(ids)).sorted()
    }

    // MARK: 词典

    func lookupDictionary(
        text: String,
        decision: TranslationDecision,
        config: TranslationConfig
    ) async throws -> DictionaryLookup {
        do {
            let content = try await performDictionary(
                text: text,
                decision: decision,
                config: config,
                jsonMode: true
            )
            return parseLookup(content)
        } catch let error as TranslationError {
            // 部分兼容供应商不认 response_format；去掉它再试一次。
            if case .http(400, _) = error {
                let content = try await performDictionary(
                    text: text,
                    decision: decision,
                    config: config,
                    jsonMode: false
                )
                return parseLookup(content)
            }
            throw error
        }
    }

    // MARK: 非流式翻译

    func translateText(
        text: String,
        decision: TranslationDecision,
        config: TranslationConfig
    ) async throws -> String {
        try await performNonStreamingChat(
            text: text,
            decision: decision,
            config: config,
            jsonMode: false
        )
    }

    private func performDictionary(
        text: String,
        decision: TranslationDecision,
        config: TranslationConfig,
        jsonMode: Bool
    ) async throws -> String {
        try await performNonStreamingChat(
            text: text,
            decision: decision,
            config: config,
            jsonMode: jsonMode
        )
    }

    private func performNonStreamingChat(
        text: String,
        decision: TranslationDecision,
        config: TranslationConfig,
        jsonMode: Bool
    ) async throws -> String {
        try Self.validate(config: config)
        guard let urlString = TranslationEndpoint.chatURLString(config.baseURL),
              let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        let body = try Self.chatBody(
            model: config.model,
            messages: TranslationPrompt.messages(text: text, decision: decision),
            stream: false,
            jsonMode: jsonMode
        )

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await perform(request)
        try Self.validate(response: response, body: data)

        guard let content = TranslationSSE.messageContent(from: data),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.badResponse
        }
        return content
    }

    private func parseLookup(_ content: String) -> DictionaryLookup {
        if let entry = DictionaryJSON.parse(content) {
            return .entry(entry)
        }
        return .raw(content)
    }

    // MARK: 长文本流式

    func streamText(
        text: String,
        decision: TranslationDecision,
        config: TranslationConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session] in
                do {
                    try Self.validate(config: config)
                    guard let urlString = TranslationEndpoint.chatURLString(config.baseURL),
                          let url = URL(string: urlString) else {
                        throw TranslationError.invalidURL
                    }

                    let body = try Self.chatBody(
                        model: config.model,
                        messages: TranslationPrompt.messages(text: text, decision: decision),
                        stream: true,
                        jsonMode: false
                    )

                    var request = URLRequest(url: url, timeoutInterval: 120)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = body

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.badResponse
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var bodyText = ""
                        for try await line in bytes.lines {
                            bodyText += line + "\n"
                            if bodyText.count > 600 { break }
                        }
                        throw TranslationHTTPError.map(status: http.statusCode, body: bodyText)
                    }

                    var parser = TranslationSSE.Parser()
                    var received = false
                    var sawDone = false

                    // 不能用 bytes.lines：AsyncLineSequence 会吞掉空行，
                    // 而 SSE 正是靠空行派发事件的。这里按字节重新切行。
                    func handleLine(_ line: String) -> Bool {
                        for event in parser.feed(line + "\n") {
                            switch event {
                            case .done:
                                return true
                            case .data(let payload):
                                if let piece = TranslationSSE.extractContent(from: payload),
                                   !piece.isEmpty {
                                    received = true
                                    continuation.yield(piece)
                                }
                            }
                        }
                        return false
                    }

                    var lineBytes: [UInt8] = []
                    lineBytes.reserveCapacity(256)

                    outer: for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A {
                            let line = String(decoding: lineBytes, as: UTF8.self)
                            lineBytes.removeAll(keepingCapacity: true)
                            if handleLine(line) {
                                sawDone = true
                                break outer
                            }
                        } else {
                            lineBytes.append(byte)
                        }
                    }

                    if !sawDone {
                        if !lineBytes.isEmpty, handleLine(String(decoding: lineBytes, as: UTF8.self)) {
                            sawDone = true
                        }
                        if !sawDone {
                            for event in parser.finish() {
                                if case .data(let payload) = event,
                                   let piece = TranslationSSE.extractContent(from: payload),
                                   !piece.isEmpty {
                                    received = true
                                    continuation.yield(piece)
                                }
                            }
                        }
                    }

                    guard received else { throw TranslationError.badResponse }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TranslationError.cancelled)
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.from(error))
                } catch {
                    continuation.finish(throwing: TranslationError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 公共小工具

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw Self.from(error)
        }
    }

    static func validate(config: TranslationConfig) throws {
        guard config.isConfigured else { throw TranslationError.notConfigured }
        try validate(baseURL: config.baseURL, apiKey: config.apiKey)
    }

    static func validate(baseURL: String, apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.notConfigured
        }
        guard TranslationEndpoint.normalizedBase(baseURL) != nil else {
            throw TranslationError.invalidURL
        }
        if TranslationEndpoint.insecureReason(baseURL) != nil {
            throw TranslationError.insecureURL
        }
    }

    static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationHTTPError.map(
                status: http.statusCode,
                body: String(data: body, encoding: .utf8) ?? ""
            )
        }
    }

    static func chatBody(
        model: String,
        messages: [ChatMessage],
        stream: Bool,
        jsonMode: Bool
    ) throws -> Data {
        // 只发 model / messages / stream（以及可选的 response_format）。
        // temperature、max_tokens 等字段在部分兼容供应商上会被直接拒绝。
        var object: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream,
        ]
        if jsonMode {
            object["response_format"] = ["type": "json_object"]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func from(_ error: URLError) -> TranslationError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost:
            return .network("网络连接不可用，请检查网络。")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .network("无法连接到供应商，请检查 Base URL 或网络。")
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return .network("TLS 连接失败，请检查 HTTPS 证书。")
        default:
            return .network(error.localizedDescription)
        }
    }
}

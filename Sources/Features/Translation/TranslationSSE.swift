import Foundation

// MARK: - SSE 流解析

/// 纯 SSE 解析器：只处理 `data:` / `[DONE]` / 注释行，
/// 把 CRLF、跨 chunk 的半行和多行 data 都收拢成完整事件。
enum TranslationSSE {

    enum Event: Equatable {
        case data(String)
        case done
    }

    struct Parser {
        private var buffer = ""
        private var dataLines: [String] = []

        mutating func feed(_ chunk: String) -> [Event] {
            buffer += chunk
            // Swift 把 "\r\n" 当成一个 Character，直接按 "\n" 切会漏掉 CRLF。
            // 先把所有换行统一成 "\n"，跨 chunk 的半个 CRLF 也能在拼接后被合并。
            buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
            buffer = buffer.replacingOccurrences(of: "\r", with: "\n")

            var events: [Event] = []

            while let newline = buffer.firstIndex(of: "\n") {
                var line = String(buffer[..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.hasSuffix("\r") { line.removeLast() }
                process(line: line, into: &events)
            }

            return events
        }

        /// 流结束时把没有换行结尾的残留行也处理掉。
        mutating func finish() -> [Event] {
            var events: [Event] = []
            if !buffer.isEmpty {
                var line = buffer
                buffer = ""
                if line.hasSuffix("\r") { line.removeLast() }
                process(line: line, into: &events)
            }
            dispatch(into: &events)
            return events
        }

        private mutating func process(line: String, into events: inout [Event]) {
            if line.isEmpty {
                dispatch(into: &events)
                return
            }
            // 以冒号开头的是注释/心跳，忽略。
            guard line.hasPrefix("data:") else { return }

            var payload = String(line.dropFirst(5))
            if payload.hasPrefix(" ") { payload.removeFirst() }

            if payload == "[DONE]" {
                dispatch(into: &events)
                events.append(.done)
            } else {
                dataLines.append(payload)
            }
        }

        private mutating func dispatch(into events: inout [Event]) {
            guard !dataLines.isEmpty else { return }
            let joined = dataLines.joined(separator: "\n")
            dataLines.removeAll()
            events.append(.data(joined))
        }
    }

    /// 流式分片：取 `choices[0].delta.content`。
    static func extractContent(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[DONE]" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [Any],
              let first = choices.first as? [String: Any] else {
            return nil
        }

        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        return nil
    }

    /// 非流式响应：取 `choices[0].message.content`，兼容 content 为分段数组的供应商。
    static func messageContent(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [Any],
              let first = choices.first as? [String: Any] else {
            return nil
        }

        if let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                return content
            }
            if let parts = message["content"] as? [Any] {
                let joined = parts.compactMap { part -> String? in
                    if let text = part as? String { return text }
                    if let dict = part as? [String: Any] {
                        return dict["text"] as? String ?? dict["content"] as? String
                    }
                    return nil
                }.joined()
                return joined.isEmpty ? nil : joined
            }
        }

        if let text = first["text"] as? String { return text }
        return nil
    }
}

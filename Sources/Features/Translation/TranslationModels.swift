import Foundation

// MARK: - 翻译模式

/// 面板里的三态开关：自动先看输入形态，词典/翻译由用户强制。
enum TranslationMode: String, CaseIterable, Identifiable, Equatable {
    case auto
    case dictionary
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .dictionary: return "词典"
        case .text: return "翻译"
        }
    }
}

// MARK: - 语言

enum TranslationLanguage: String, Equatable {
    case chinese
    case english
    case other

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "英语"
        case .other: return "外文"
        }
    }

    /// AVSpeechSynthesizer 的语言代码；不认识的语种按英文朗读。
    var speechCode: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english, .other: return "en-US"
        }
    }
}

// MARK: - 长文本目标语言

enum LongTextTarget: String, CaseIterable, Identifiable, Equatable {
    case auto
    case chinese
    case english

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .chinese: return "中文"
        case .english: return "英文"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "中文长文本译成英文，其他语言译成中文"
        case .chinese: return "长文本一律译成中文"
        case .english: return "长文本一律译成英文"
        }
    }
}

// MARK: - 一次分类结果

struct TranslationDecision: Equatable {
    let mode: TranslationMode
    let source: TranslationLanguage
    let target: TranslationLanguage

    var isDictionary: Bool { mode == .dictionary }

    /// 面板底部和设置页展示的统一方向文案。
    var label: String {
        "\(source.label) → \(target.label) · \(mode == .dictionary ? "词典" : "翻译")"
    }
}

// MARK: - 聊天消息

struct ChatMessage: Encodable, Equatable {
    let role: String
    let content: String
}

// MARK: - 双语词典结构

struct DictionarySense: Equatable {
    var partOfSpeech: String
    var translation: String
    var definition: String
}

struct DictionaryExample: Equatable {
    var source: String
    var target: String
}

struct DictionaryEntry: Equatable {
    var word: String
    var phonetic: String
    var senses: [DictionarySense]
    var examples: [DictionaryExample]
    var synonyms: [String]

    var isEmpty: Bool {
        word.isEmpty && senses.isEmpty && examples.isEmpty
    }
}

/// 词典结果的容错解析。
/// 模型有时会包一层 ```json 围栏，也可能少给字段；这里尽量把能用的部分捞出来，
/// 实在解析不了就返回 nil，让调用方把原文当普通文本展示，避免白屏。
enum DictionaryJSON {

    static func stripFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            } else {
                text.removeFirst(3)
                if text.lowercased().hasPrefix("json") {
                    text.removeFirst(4)
                }
            }
        }

        if let fence = text.range(of: "```", options: .backwards) {
            text = String(text[..<fence.lowerBound])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 取第一个 `{` 到最后一个 `}`，容忍模型在 JSON 前后加说明文字。
    static func payload(from raw: String) -> String? {
        let text = stripFences(raw)
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    static func parse(_ raw: String) -> DictionaryEntry? {
        guard let payload = payload(from: raw),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let word = firstString(in: object, keys: ["word", "headword", "term"])
        let phonetic = firstString(in: object, keys: ["phonetic", "pronunciation", "pinyin", "ipa"])

        var senses = parseSenses(object)
        if senses.isEmpty {
            let translation = firstString(in: object, keys: ["translation", "meaning"])
            let definition = firstString(in: object, keys: ["definition", "explanation"])
            if !translation.isEmpty || !definition.isEmpty {
                senses = [DictionarySense(
                    partOfSpeech: firstString(in: object, keys: ["partOfSpeech", "pos"]),
                    translation: translation,
                    definition: definition
                )]
            }
        }
        senses = senses.filter { !$0.translation.isEmpty || !$0.definition.isEmpty }
        guard !senses.isEmpty else { return nil }

        let examples = parseExamples(object)
        let synonyms = parseSynonyms(object)

        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            senses: senses,
            examples: examples,
            synonyms: synonyms
        )
    }

    // MARK: 私有解析

    private static func parseSenses(_ object: [String: Any]) -> [DictionarySense] {
        if let array = object["senses"] as? [Any] {
            return array.compactMap { item -> DictionarySense? in
                if let text = item as? String {
                    return DictionarySense(partOfSpeech: "", translation: text, definition: "")
                }
                guard let dict = item as? [String: Any] else { return nil }
                return DictionarySense(
                    partOfSpeech: firstString(in: dict, keys: ["partOfSpeech", "pos", "type"]),
                    translation: firstString(in: dict, keys: ["translation", "meaning", "target"]),
                    definition: firstString(in: dict, keys: ["definition", "explanation", "source"])
                )
            }
        }

        // 兼容类 Ulysses/系统词典的 meanings → definitions 结构。
        guard let meanings = object["meanings"] as? [Any] else { return [] }
        var result: [DictionarySense] = []
        for meaning in meanings {
            guard let meaningDict = meaning as? [String: Any] else { continue }
            let inheritedPOS = firstString(in: meaningDict, keys: ["partOfSpeech", "pos", "type"])
            if let definitions = meaningDict["definitions"] as? [Any] {
                for item in definitions {
                    guard let dict = item as? [String: Any] else { continue }
                    result.append(DictionarySense(
                        partOfSpeech: inheritedPOS.isEmpty
                            ? firstString(in: dict, keys: ["partOfSpeech", "pos"])
                            : inheritedPOS,
                        translation: firstString(in: dict, keys: ["translation", "meaning", "target"]),
                        definition: firstString(in: dict, keys: ["definition", "explanation"])
                    ))
                }
            } else {
                result.append(DictionarySense(
                    partOfSpeech: inheritedPOS,
                    translation: firstString(in: meaningDict, keys: ["translation", "meaning"]),
                    definition: firstString(in: meaningDict, keys: ["definition", "explanation"])
                ))
            }
        }
        return result
    }

    private static func parseExamples(_ object: [String: Any]) -> [DictionaryExample] {
        guard let array = object["examples"] as? [Any] else { return [] }
        return array.compactMap { item -> DictionaryExample? in
            if let text = item as? String, !text.isEmpty {
                return DictionaryExample(source: text, target: "")
            }
            guard let dict = item as? [String: Any] else { return nil }
            let source = firstString(in: dict, keys: ["source", "sentence", "original", "example"])
            let target = firstString(in: dict, keys: ["target", "translation", "translated"])
            guard !source.isEmpty || !target.isEmpty else { return nil }
            return DictionaryExample(source: source, target: target)
        }
    }

    private static func parseSynonyms(_ object: [String: Any]) -> [String] {
        if let array = object["synonyms"] as? [Any] {
            return array.compactMap { item in
                if let text = item as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return nil
            }
        }
        if let text = object["synonyms"] as? String {
            return text.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = object[key] as? NSNumber {
                return number.stringValue
            }
        }
        return ""
    }
}

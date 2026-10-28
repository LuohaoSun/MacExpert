import Foundation

// MARK: - 输入形态分类

/// 纯逻辑：先看输入长什么样，再决定发词典请求还是长文本请求。
/// 不依赖网络和 UI，单元测试直接喂字符串。
enum TranslationClassifier {

    private static let terminalPunctuation: Set<Character> = [
        ".", "!", "?", ";", "。", "！", "？", "；", "…",
    ]

    static func decide(
        _ raw: String,
        mode: TranslationMode = .auto,
        longTextTarget: LongTextTarget = .auto
    ) -> TranslationDecision? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let source = language(of: text)

        let resolvedMode: TranslationMode
        switch mode {
        case .auto:
            resolvedMode = isDictionaryCandidate(text) ? .dictionary : .text
        case .dictionary, .text:
            resolvedMode = mode
        }

        let target: TranslationLanguage
        if resolvedMode == .dictionary {
            // 词典永远做双向互译，和长文本的目标语言设置无关。
            target = source == .chinese ? .english : .chinese
        } else {
            switch longTextTarget {
            case .auto:
                target = source == .chinese ? .english : .chinese
            case .chinese:
                target = .chinese
            case .english:
                target = .english
            }
        }

        return TranslationDecision(mode: resolvedMode, source: source, target: target)
    }

    static func language(of text: String) -> TranslationLanguage {
        if hanCount(text) > 0 { return .chinese }
        if text.contains(where: { $0.isLatinLetter }) { return .english }
        return .other
    }

    static func hanCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isHan($1) ? 1 : 0) }
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,   // 扩展 A
             0x4E00...0x9FFF,   // 基本区
             0xF900...0xFAFF,   // 兼容表意
             0x20000...0x2FA1F, // 扩展 B–F
             0x30000...0x3134F: // 扩展 G
            return true
        default:
            return false
        }
    }

    /// 只统计含字母的 token；纯标点、纯数字不算词。
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace })
            .filter { token in token.contains { $0.isLetter } }
            .count
    }

    static func isDictionaryCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 多行一定是长文本，词典面板不适合装段落。
        guard !trimmed.contains("\n"), !trimmed.contains("\r") else { return false }

        let han = hanCount(trimmed)
        if han > 0 { return han <= 4 }

        let words = wordCount(trimmed)
        guard words >= 1 else { return false }
        if words == 1 { return true }
        guard words <= 3 else { return false }
        return trimmed.count <= 30 && !endsWithTerminalPunctuation(trimmed)
    }

    static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return terminalPunctuation.contains(last)
    }
}

private extension Character {
    var isLatinLetter: Bool {
        unicodeScalars.contains { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }
    }
}

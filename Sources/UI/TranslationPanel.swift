import AppKit
import AVFoundation
import SwiftUI

// MARK: - 面板

struct TranslationPanel: View {

    @ObservedObject var feature: TranslationFeature
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    private let speaker = SpeechSpeaker.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            inputSection
            Divider()
            resultSection
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 360)
    }

    private var isBusy: Bool {
        switch feature.state {
        case .loading, .streaming: return true
        default: return false
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            Text("热键翻译")
                .font(.headline)

            Spacer(minLength: 8)

            Picker("模式", selection: modeBinding) {
                ForEach(TranslationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("翻译模式")

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("打开翻译设置")
            .accessibilityLabel("打开翻译设置")
        }
        // 全尺寸内容视图下，左上角是红绿灯按钮；内容本身从标题栏下方开始，
        // 这里只保留与卡片一致的左右留白。
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .padding(.bottom, 9)
    }

    private var modeBinding: Binding<TranslationMode> {
        Binding(
            get: { feature.mode },
            set: { feature.setMode($0) }
        )
    }

    // MARK: 输入

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TranslationInputView(
                    text: $feature.input,
                    focusRequest: feature.focusRequest,
                    onSubmit: { feature.submit() },
                    onCancel: onClose
                )

                if feature.input.isEmpty {
                    Text("输入要翻译的单词或文本…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 11)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text(feature.state == .loading ? "正在请求供应商…" : "正在翻译…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isBusy {
                    Button("取消") { feature.cancelTranslation() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button {
                        feature.submit()
                    } label: {
                        Label("翻译", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(feature.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 结果

    private var resultSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: 1)
                        .id("panel-top")
                    resultContent
                    Color.clear
                        .frame(height: 1)
                        .id("panel-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .onChange(of: feature.state) { _, newValue in
                if case .streaming = newValue {
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo("panel-bottom", anchor: .bottom)
                    }
                } else {
                    // 长文完成后回到顶部，让用户从第一段开始读，而不是停在结尾。
                    withAnimation(.linear(duration: 0.12)) {
                        proxy.scrollTo("panel-top", anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var resultContent: some View {
        switch feature.state {
        case .idle:
            idleView
        case .loading:
            loadingView
        case .streaming(let text):
            streamingView(text)
        case .translated(let text):
            translatedView(text)
        case .dictionary(let entry):
            dictionaryView(entry)
        case .plain(let text):
            plainView(text)
        case .failed(let message):
            failureView(message)
        case .notConfigured:
            notConfiguredView
        }
    }

    private var idleView: some View {
        Group {
            if !feature.isConfigured {
                notConfiguredView
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("输入内容后按回车")
                        .font(.callout)
                    Text("单词会给出双语词典释义；长文本会按设置流式或一次性输出，并保留段落与 Markdown。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var notConfiguredView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("先配置供应商", systemImage: "key.horizontal")
                .font(.headline)

            Text("热键翻译使用你自己的 OpenAI Chat Completions 兼容服务。填入 Base URL、API Key 和模型后即可使用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("打开设置") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在请求供应商…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("取消") { feature.cancelTranslation() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func streamingView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("译文")
                    .font(.headline)
                ProgressView()
                    .controlSize(.small)
                Spacer(minLength: 8)
                Button {
                    copy(text)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("重新翻译") { feature.submit() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func translatedView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("译文")
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    copy(text)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("重新翻译") { feature.submit() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plainView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("词典结果")
                    .font(.headline)
                Text("未解析成结构化词典，按原文显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    copy(text)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("翻译失败", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button("重试") { feature.submit() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: 词典

    private func dictionaryView(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.word.isEmpty ? feature.submittedText : entry.word)
                    .font(.system(size: 26, weight: .semibold))

                if !entry.phonetic.isEmpty {
                    Text(entry.phonetic)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    let spoken = entry.word.isEmpty ? feature.submittedText : entry.word
                    speaker.speak(spoken, language: feature.lastDecision?.source.speechCode ?? "en-US")
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    copy(dictionaryText(entry))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(senseGroups(entry.senses)) { group in
                VStack(alignment: .leading, spacing: 5) {
                    if !group.partOfSpeech.isEmpty {
                        Text(group.partOfSpeech)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    ForEach(Array(group.senses.enumerated()), id: \.offset) { _, sense in
                        VStack(alignment: .leading, spacing: 2) {
                            if !sense.translation.isEmpty {
                                Text(sense.translation)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !sense.definition.isEmpty {
                                Text(sense.definition)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if !entry.examples.isEmpty {
                Divider()
                Text("例句")
                    .font(.headline)
                ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 2) {
                        if !example.source.isEmpty {
                            Text(example.source)
                                .font(.callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !example.target.isEmpty {
                            Text(example.target)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !entry.synonyms.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("近义词")
                        .font(.headline)
                    Text(entry.synonyms.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct SenseGroup: Identifiable {
        let id: String
        let partOfSpeech: String
        let senses: [DictionarySense]
    }

    private func senseGroups(_ senses: [DictionarySense]) -> [SenseGroup] {
        var order: [String] = []
        var buckets: [String: [DictionarySense]] = [:]

        for sense in senses {
            let key = sense.partOfSpeech.isEmpty ? "释义" : sense.partOfSpeech
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(sense)
        }

        return order.map { key in
            SenseGroup(id: key, partOfSpeech: key, senses: buckets[key] ?? [])
        }
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text("回车翻译 · Shift+回车换行 · Esc 关闭")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if !feature.directionLabel.isEmpty {
                Text(feature.directionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035))
    }

    // MARK: 工具

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func dictionaryText(_ entry: DictionaryEntry) -> String {
        var lines: [String] = []
        let headword = entry.word.isEmpty ? feature.submittedText : entry.word
        lines.append(entry.phonetic.isEmpty ? headword : "\(headword) [\(entry.phonetic)]")

        for sense in entry.senses {
            var line = "- "
            if !sense.partOfSpeech.isEmpty { line += "\(sense.partOfSpeech) " }
            line += sense.translation
            if !sense.definition.isEmpty { line += "（\(sense.definition)）" }
            lines.append(line)
        }

        for example in entry.examples {
            lines.append("例句：\(example.source)\(example.target.isEmpty ? "" : " → \(example.target)")")
        }

        if !entry.synonyms.isEmpty {
            lines.append("近义词：\(entry.synonyms.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - 输入框

/// NSTextView 包装：多行、回车提交、Shift+回车换行、Esc 关闭。
private struct TranslationInputView: NSViewRepresentable {

    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        DispatchQueue.main.async {
            if let window = textView.window {
                window.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                if let window = textView.window {
                    window.makeFirstResponder(textView)
                }
                if !textView.string.isEmpty {
                    textView.selectAll(nil)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranslationInputView
        var lastFocusRequest = -1

        init(parent: TranslationInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false
                }
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - 朗读

final class SpeechSpeaker: ObservableObject {

    static let shared = SpeechSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}

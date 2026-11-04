import AppKit
import SwiftUI

/// 主窗口里的「热键翻译」设置页。
struct TranslationView: View {

    @ObservedObject private var feature = TranslationFeature.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared

    var body: some View {
        PageScaffold {
            if let failure = hotkeyFailure {
                hotkeyWarning(failure)
            }
            statusCard
            providerCard
            behaviorCard
            privacyCard
        }
        .onAppear {
            feature.loadKeyIfNeeded()
            syncDrafts()
        }
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(statusSubtitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        Text("启用")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Toggle("", isOn: enabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("启用热键翻译")
                    }
                    .fixedSize()
                }

                HStack(spacing: 10) {
                    Button {
                        feature.openPanel()
                    } label: {
                        Label("打开翻译面板", systemImage: "character.bubble")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!feature.enabled)

                    Text("也可以随时按")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HotkeyCaps(caps: ["⌥", "空格"])
                    Text("呼出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .offset(x: -10, y: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hotkeyFailure: HotkeyFailure? {
        hotkeys.failures.first { $0.id == HotkeyID.translation }
    }

    private var statusTitle: String {
        if !feature.enabled { return "热键翻译已关闭" }
        if hotkeyFailure != nil { return "快捷键被占用" }
        if !feature.isConfigured { return "尚未配置翻译服务" }
        return "热键翻译已启用"
    }

    private var statusSubtitle: String {
        if !feature.enabled { return "开启后可随时按 ⌥空格 呼出翻译面板" }
        if hotkeyFailure != nil { return "⌥空格 已被其他应用占用；你仍可点击下方按钮打开翻译面板" }
        if !feature.isConfigured { return "填写下方接口地址、API 密钥和模型后即可使用" }
        return "在任意应用中按 ⌥空格 呼出面板，自动识别查词与长文翻译"
    }

    private var statusSubtitleColor: Color {
        if !feature.enabled { return .secondary }
        if hotkeyFailure != nil || !feature.isConfigured { return .orange }
        return .secondary
    }

    private var statusColor: Color {
        if !feature.enabled { return .secondary }
        if hotkeyFailure != nil || !feature.isConfigured { return .orange }
        return Theme.green
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { feature.enabled },
            set: { feature.enabled = $0 }
        )
    }

    private func hotkeyWarning(_ failure: HotkeyFailure) -> some View {
        CardSurface(fill: Color.orange.opacity(0.08), borderOpacity: 0.18) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("快捷键 ⌥空格 注册失败")
                        .font(.callout)
                    Text("\(failure.message)。请关闭占用该快捷键的应用后点击重试。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button("重试") {
                    feature.syncHotkey()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - 翻译服务

    private var providerCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("翻译服务")
                        .font(.headline)
                    Text("支持 OpenAI 兼容接口（如 OpenAI、DeepSeek、本地网关等），仅发送待翻译文本与必要参数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsRow("服务地址 (Base URL)") {
                    TextField("https://api.openai.com/v1", text: $feature.draftBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit(save)
                }

                SettingsRow("API 密钥", detail: "仅保存在本机，当前登录用户可读") {
                    SecureField("sk-…", text: $feature.draftKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit(save)
                }

                SettingsRow("模型") {
                    HStack(spacing: 8) {
                        TextField("gpt-4o-mini", text: $feature.draftModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 210)
                            .onSubmit(save)

                        if !feature.models.isEmpty {
                            Menu {
                                ForEach(feature.models, id: \.self) { id in
                                    Button(id) { feature.draftModel = id }
                                }
                                Divider()
                                Button("重新获取") { fetchModels() }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("从已获取的模型中选择")
                        }

                        Button {
                            fetchModels()
                        } label: {
                            if feature.isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("获取模型")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(feature.isFetchingModels)
                    }
                    .frame(width: 320, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    if let connectionMessage = feature.connectionMessage {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundStyle(feature.connectionIsError ? Color.red : Color.secondary)
                            .lineLimit(2)
                    } else {
                        Text(saveStateText)
                            .font(.caption)
                            .foregroundStyle(saveStateColor)
                    }

                    Spacer(minLength: 12)

                    Button("测试连接") { fetchModels() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(feature.isFetchingModels)

                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private var saveStateText: String {
        if case .failed(let message) = feature.saveState { return message }
        if feature.hasUnsavedChanges { return "有未保存的更改" }
        switch feature.saveState {
        case .idle:
            return feature.isConfigured ? "配置已保存" : "尚未配置 API 密钥"
        case .saved:
            return "已保存"
        case .failed:
            return ""
        }
    }

    private var saveStateColor: Color {
        if case .failed = feature.saveState { return .red }
        if feature.hasUnsavedChanges { return .orange }
        switch feature.saveState {
        case .failed: return .red
        case .saved: return Theme.green
        case .idle: return .secondary
        }
    }

    // MARK: - 行为

    private var behaviorCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("翻译行为")
                    .font(.headline)

                SettingsRow("长文本目标语言", detail: feature.longTextTarget.detail) {
                    Picker("长文本目标语言", selection: longTextTargetBinding) {
                        ForEach(LongTextTarget.allCases) { target in
                            Text(target.label).tag(target)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Divider()

                SettingsRow("流式输出", detail: "长文本边生成边显示；关闭后等完整结果一次性显示") {
                    Toggle("", isOn: streamOutputBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("流式输出")
                }

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    ruleRow("词典", "1–4 个汉字，或 1–3 个外文单词（不含句末标点）自动进入双语词典")
                    ruleRow("翻译", "句子与段落按长文本翻译，自动保留段落格式、Markdown 与代码块")
                    ruleRow("方向", "词典模式固定中英互译；长文本按上方所选的目标语言输出")
                }
            }
        }
    }

    private func ruleRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Badge(text: title, color: title == "词典" ? Theme.accent : .secondary)
                .frame(width: 34, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var longTextTargetBinding: Binding<LongTextTarget> {
        Binding(
            get: { feature.longTextTarget },
            set: { feature.longTextTarget = $0 }
        )
    }

    private var streamOutputBinding: Binding<Bool> {
        Binding(
            get: { feature.streamOutput },
            set: { feature.streamOutput = $0 }
        )
    }

    // MARK: - 隐私

    private var privacyCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 7) {
                Text("隐私")
                    .font(.headline)
                Text("翻译时，输入的文本仅直接发送给你配置的翻译服务，不会经过任何第三方中转。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("API 密钥仅保存在本机应用支持目录中；应用日志不会记录密钥或任何输入文本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 动作

    private func syncDrafts() {
        feature.draftBaseURL = feature.baseURL
        feature.draftModel = feature.model
        feature.draftKey = feature.apiKey
    }

    private func save() {
        let key = feature.draftKey.isEmpty ? feature.apiKey : feature.draftKey
        if let error = feature.saveProvider(
            baseURL: feature.draftBaseURL,
            model: feature.draftModel,
            apiKey: key
        ) {
            feature.saveState = .failed(error.localizedDescription)
            return
        }
        feature.connectionMessage = nil
        feature.saveState = .saved
    }

    private func fetchModels() {
        let base = feature.draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (feature.draftKey.isEmpty ? feature.apiKey : feature.draftKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty else {
            feature.connectionIsError = true
            feature.connectionMessage = "请先填写接口地址。"
            return
        }
        guard !key.isEmpty else {
            feature.connectionIsError = true
            feature.connectionMessage = "请先填写 API 密钥。"
            return
        }

        feature.connectionMessage = "正在连接…"
        feature.connectionIsError = false

        Task { @MainActor in
            let error = await feature.fetchModels(baseURL: base, apiKey: key)
            if let error {
                feature.connectionIsError = true
                feature.connectionMessage = error.localizedDescription
            } else {
                feature.connectionIsError = false
                feature.connectionMessage = feature.models.isEmpty
                    ? "连接成功，但服务未返回模型列表，可手动输入模型名称。"
                    : "连接成功，已获取 \(feature.models.count) 个可用模型。"
            }
        }
    }
}

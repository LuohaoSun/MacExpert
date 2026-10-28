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
                    HotkeyCaps(caps: ["⌥", "Space"])
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
        if !feature.enabled { return "热键翻译已暂停" }
        if hotkeyFailure != nil { return "快捷键被占用" }
        if !feature.isConfigured { return "等待配置供应商" }
        return "热键翻译已启用"
    }

    private var statusSubtitle: String {
        if !feature.enabled { return "打开开关后，⌥Space 才会注册为全局热键。" }
        if hotkeyFailure != nil { return "⌥Space 已被其他应用占用；仍可点「打开翻译面板」使用。" }
        if !feature.isConfigured { return "填写下方 Base URL、API Key 和模型后即可翻译。" }
        return "在任意应用按 ⌥Space 呼出面板；中文 ↔ 英文自动互译。"
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
                    Text("⌥Space 注册失败")
                        .font(.callout)
                    Text("\(failure.message)（OSStatus \(failure.status)）。关掉占用快捷键的应用后，重新打开本页会自动重试。")
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

    // MARK: - 供应商

    private var providerCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("供应商")
                        .font(.headline)
                    Text("任何 OpenAI Chat Completions 兼容服务都可以；只发送 model、messages 和 stream。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: $feature.draftBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .onSubmit(save)
                }

                SettingsRow("API Key", detail: "保存在本机应用支持目录，仅当前用户可读") {
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
        switch feature.saveState {
        case .idle:
            return feature.isConfigured ? "配置已保存" : "尚未配置密钥"
        case .saved:
            return "已保存"
        case .failed(let message):
            return message
        }
    }

    private var saveStateColor: Color {
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

                SettingsRow("长文本目标语言") {
                    Picker("长文本目标语言", selection: longTextTargetBinding) {
                        ForEach(LongTextTarget.allCases) { target in
                            Text(target.label).tag(target)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Text(feature.longTextTarget.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    ruleRow("词典", "中文 1–4 个汉字；外文 1 个词，或 2–3 个词且 ≤30 字符、无句末标点")
                    ruleRow("翻译", "其余输入按长文本处理，保留段落、Markdown、代码块、专有名词和数字")
                    ruleRow("方向", "词典固定中英互译；长文本方向由上面的设置决定，自动即「翻成另一种语言」")
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
                Text("翻译时，输入文本会发送到你配置的供应商；请求不经过 MacExpert 的中转服务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("API Key 只保存在本机应用支持目录（文件权限 0600，仅当前用户可读）；应用日志不记录 Key，也不记录你输入的文本。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            feature.connectionMessage = "先填写 Base URL。"
            return
        }
        guard !key.isEmpty else {
            feature.connectionIsError = true
            feature.connectionMessage = "先填写 API Key。"
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
                    ? "连接成功，但供应商没有返回模型列表。"
                    : "连接成功，找到 \(feature.models.count) 个模型。"
            }
        }
    }
}

import AppKit
import SwiftUI

/// 主窗口里的「剪贴板敲入」页：状态卡 + 设置卡。
struct TypeClipView: View {
    @ObservedObject private var clip = TypeClipFeature.shared
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared

    var body: some View {
        PageScaffold {
            if !app.trusted {
                PermissionBanner(
                    title: "需要辅助功能权限，授权后才能敲入。",
                    onRecheck: { app.refreshTrust() }
                )
            }
            statusCard
            settingsCard
            advancedCard
            shortcutCard
            useCaseCard
        }
        .alert(
            "开启诊断日志？",
            isPresented: Binding(
                get: { clip.debugConfirmPending },
                set: { if !$0 { clip.debugConfirmPending = false } }
            )
        ) {
            Button("取消", role: .cancel) {
                clip.debugConfirmPending = false
            }
            Button("开启并记录明文", role: .destructive) {
                clip.debugLog = true
                clip.debugConfirmPending = false
            }
        } message: {
            Text("开启后会记录被敲入的字符明文，等于剪贴板内容。只在排查问题时开启，完成后请立即关闭。")
        }
    }

    // MARK: - 状态

    private var statusCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusSubtitle)
                            .font(.caption)
                            .foregroundStyle(statusSubtitleColor)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(statusSubtitle)
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
                            .accessibilityLabel("启用剪贴板敲入")
                    }
                    .fixedSize()
                }

                if clip.isActive, let value = clip.progress {
                    ProgressView(value: value)
                        .tint(.orange)
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

    private var statusTitle: String {
        if !app.trusted { return "等待辅助功能权限" }
        if !clip.enabled { return "剪贴板敲入已暂停" }
        if !clip.clipboardOK { return "等待可敲入文本" }

        switch clip.phase {
        case .idle: return "剪贴板敲入已启用"
        case .typing: return "正在敲入…"
        case .done: return "敲入完成"
        case .aborted: return "已中断"
        case .failed: return "无法敲入"
        }
    }

    private var statusSubtitle: String {
        if !app.trusted { return "授权后按 ⌃⌘V 开始敲入" }
        if !clip.enabled { return "热键已暂停，打开开关后恢复" }
        if !clip.clipboardOK { return clipboardActionHint }
        if let error = clip.lastError { return error }
        if clip.isActive { return "\(clipboardLine) · 再按一次 ⌃⌘V 中断" }
        return "\(clipboardLine) · 按 ⌃⌘V 开始"
    }

    /// 剪贴板不可敲入时给下一步动作，不重复状态标题。
    private var clipboardActionHint: String {
        let summary = clip.clipboardSummary
        if summary.contains("图像") { return "剪贴板是图片，无法敲入；先复制一段文字。" }
        if summary.contains("文件") { return "剪贴板是文件，无法敲入；先复制一段文字。" }
        if summary.contains("空白") { return "剪贴板只有空白字符；先复制一段文字。" }
        return "剪贴板没有文本；先复制一段文字。"
    }

    private var statusSubtitleColor: Color {
        if !app.trusted || !clip.enabled || !clip.clipboardOK { return .secondary }
        return clip.lastError == nil ? .secondary : .red
    }

    /// 文本摘要补上「剪贴板」标签；错误摘要本身就以「剪贴板」开头，不再重复。
    private var clipboardLine: String {
        clip.clipboardSummary.hasPrefix("剪贴板")
            ? clip.clipboardSummary
            : "剪贴板：\(clip.clipboardSummary)"
    }

    private var statusColor: Color {
        if !app.trusted { return .orange }
        if !clip.enabled { return .secondary }
        switch clip.phase {
        case .idle:
            return clip.clipboardOK ? Theme.accent : .secondary
        default:
            return clip.phase.color
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { clip.enabled },
            set: { clip.enabled = $0 }
        )
    }

    // MARK: - 敲入设置

    private var settingsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("敲入设置")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    SettingsRow(leading: "速度") {
                        Slider(value: paceBinding, in: 50...500)
                        Text("\(Int(clip.paceMs))ms")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    Text(clip.manual ? effectiveDetail : clip.derivedDetail)
                        .font(.caption)
                        .foregroundStyle(clip.manual ? Color.orange : Color.secondary)
                        .padding(.leading, 90)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    SettingsRow(leading: "输入法") {
                        Picker("输入法", selection: imeBinding) {
                            ForEach(IMEMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Text(clip.imeMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 90)
                }

                Divider()

                SettingsRow(
                    "结尾按回车",
                    detail: "敲入完成后补一个 Return，适合提交命令"
                ) {
                    Toggle("", isOn: enterBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var effectiveDetail: String {
        let p = clip.effectiveRaw
        return "手动 · 间隔 \(Int(p.interval))ms · 按住 \(Int(p.hold))ms · 抖动 \(Int(p.jitter))ms · 修饰键 \(Int(p.modifierDelay))ms"
    }

    // MARK: - 高级参数

    private var advancedCard: some View {
        CardSurface {
            DisclosureRow(
                "高级参数",
                systemImage: "slider.horizontal.3",
                isExpanded: advancedBinding
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow("手动覆盖速度轴") {
                        Toggle("", isOn: manualBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    let d = TypeClipFeature.derived(paceMs: clip.paceMs)
                    sliderRow(
                        "字符间隔",
                        value: rawBinding(\.intervalMs, fallback: d.interval),
                        range: 50...500
                    )
                    sliderRow(
                        "按住时长",
                        value: rawBinding(\.holdMs, fallback: d.hold),
                        range: 20...150
                    )
                    sliderRow(
                        "随机抖动",
                        value: rawBinding(\.jitterMs, fallback: d.jitter),
                        range: 0...80
                    )
                    sliderRow(
                        "修饰键延迟",
                        value: rawBinding(\.modifierDelayMs, fallback: d.modifierDelay),
                        range: 0...200
                    )

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(clip.manual
                             ? "拖动滑杆即使用手动参数；移动速度滑杆会自动退出。"
                             : "拖动任一滑杆会自动开启手动覆盖；仅在速度轴与实测不符时使用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if clip.manual {
                            Button("恢复自动") { clip.manual = false }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 12)

            DisclosureRow(
                "诊断日志",
                systemImage: "doc.text.magnifyingglass",
                isExpanded: diagnosticsBinding
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(
                        "记录逐字符注入路径",
                        detail: "排查 # 退化成 3 这类问题时再打开"
                    ) {
                        Toggle("", isOn: debugBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    LogPathRow()

                    Text(clip.debugLog
                         ? "正在记录被敲入的字符明文（等于剪贴板内容），排查完请立刻关闭"
                         : "开启后会记录被敲入的字符明文（等于剪贴板内容），开启前会再次确认")
                        .font(.caption)
                        .foregroundStyle(clip.debugLog ? Color.orange : Color.secondary)
                }
            }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 10
    ) -> some View {
        SettingsRow(leading: title) {
            Slider(value: rounded(value, step: step), in: range)
            Text("\(Int(value.wrappedValue))ms")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func rounded(_ binding: Binding<Double>, step: Double) -> Binding<Double> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = ($0 / step).rounded() * step }
        )
    }

    private func rawBinding(
        _ keyPath: ReferenceWritableKeyPath<TypeClipFeature, Double>,
        fallback: Double
    ) -> Binding<Double> {
        Binding(
            get: { clip.manual ? clip[keyPath: keyPath] : fallback },
            set: { newValue in
                if !clip.manual { clip.manual = true }
                clip[keyPath: keyPath] = newValue
            }
        )
    }

    // MARK: - 快捷键与场景

    private var shortcutCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("快捷键")
                    .font(.headline)
                SettingsRow("敲入剪贴板") {
                    HotkeyCaps(caps: ["⌃", "⌘", "V"])
                }
                SettingsRow("敲入并回车") {
                    HotkeyCaps(caps: ["⌃", "⌘", "↩"])
                }
                if let failure = typeClipHotkeyFailure {
                    Text("热键未注册：\(failure.message)。请检查系统键盘快捷键冲突。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("敲入过程中再按一次任意热键即可中断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var typeClipHotkeyFailure: HotkeyFailure? {
        hotkeys.failures.first {
            $0.id == HotkeyID.typeClip || $0.id == HotkeyID.typeClipEnter
        }
    }

    private var useCaseCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 7) {
                Text("适用场景")
                    .font(.headline)
                Text("远程桌面、堡垒机、虚拟机，以及任何 ⌘V 被禁用或剪贴板不互通的地方。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("远程端完全拦截合成键盘事件时，本工具无法绕过。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 绑定

    private var paceBinding: Binding<Double> {
        Binding(
            get: { clip.paceMs },
            set: { clip.paceMs = (($0 / 10).rounded() * 10) }
        )
    }

    private var imeBinding: Binding<IMEMode> {
        Binding(get: { clip.imeMode }, set: { clip.imeMode = $0 })
    }

    private var enterBinding: Binding<Bool> {
        Binding(get: { clip.pressEnterSuffix }, set: { clip.pressEnterSuffix = $0 })
    }

    private var manualBinding: Binding<Bool> {
        Binding(get: { clip.manual }, set: { clip.manual = $0 })
    }

    private var advancedBinding: Binding<Bool> {
        Binding(
            get: { clip.advancedExpanded },
            set: { clip.advancedExpanded = $0 }
        )
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { clip.diagnosticsExpanded },
            set: { clip.diagnosticsExpanded = $0 }
        )
    }

    private var debugBinding: Binding<Bool> {
        Binding(
            get: { clip.debugLog },
            set: { newValue in
                if newValue {
                    clip.debugConfirmPending = true
                } else {
                    clip.debugLog = false
                }
            }
        )
    }
}

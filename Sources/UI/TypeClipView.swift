import AppKit
import SwiftUI

/// 主窗口里的「剪贴板敲入」页：状态卡 + 设置卡。
struct TypeClipView: View {
    @ObservedObject private var clip = TypeClipFeature.shared
    @ObservedObject private var app = AppState.shared

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
    }

    // MARK: - 状态

    private var statusCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(clip.phase.color)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("状态：\(clip.phase.label)")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.headline)
                        Text(clip.clipboardSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(clip.clipboardSummary)
                    }

                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        statusActions
                    }
                    .fixedSize()
                }

                if clip.isActive, let value = clip.progress {
                    ProgressView(value: value)
                        .tint(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        if clip.isActive {
            Button("中断敲入", role: .destructive) { clip.cancel() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        } else if app.trusted && clip.clipboardOK {
            Button("敲入剪贴板") { clip.handleHotkey(enter: false) }
                .buttonStyle(.borderedProminent)
        } else {
            Button("敲入剪贴板") { clip.handleHotkey(enter: false) }
                .buttonStyle(.bordered)
                .disabled(true)
        }
        Button("刷新") { clip.refreshPasteboard(force: true) }
            .buttonStyle(.bordered)
    }

    private var headline: String {
        switch clip.phase {
        case .idle: return "等待敲入"
        case .typing: return "正在敲入…"
        case .done: return "敲入完成"
        case .aborted: return "已中断"
        case .failed: return "无法敲入"
        }
    }

    // MARK: - 敲入设置

    private var settingsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("敲入设置")
                    .font(.headline)

                SettingsRow(leading: "速度") {
                    Slider(value: paceBinding, in: 50...500)
                    Text("\(Int(clip.paceMs))ms")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                Divider()

                SettingsRow(leading: "输入法") {
                    Picker("输入法", selection: imeBinding) {
                        ForEach(IMEMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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

                Text(clip.manual ? effectiveDetail : clip.derivedDetail)
                    .font(.caption)
                    .foregroundStyle(clip.manual ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            DisclosureGroup(isExpanded: advancedBinding) {
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
                .padding(.top, 8)
            } label: {
                Label("高级参数", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }

            Divider()
                .padding(.vertical, 12)

            DisclosureGroup(isExpanded: diagnosticsBinding) {
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
                         ? "打开后日志会含被敲入的字符明文（等于剪贴板内容），排查完请关掉"
                         : "关闭时日志只记配置与统计，不含剪贴板内容")
                        .font(.caption)
                        .foregroundStyle(clip.debugLog ? Color.orange : Color.secondary)
                }
                .padding(.top, 8)
            } label: {
                Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
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
                Text("敲入过程中再按一次任意热键即可中断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        Binding(get: { clip.debugLog }, set: { clip.debugLog = $0 })
    }
}

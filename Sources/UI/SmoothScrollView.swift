import AppKit
import SwiftUI

/// 主窗口里的「平滑滚动」页。
struct SmoothScrollView: View {

    @ObservedObject private var scroll = SmoothScrollFeature.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        PageScaffold {
            if scroll.enabled, !app.trusted {
                PermissionBanner(
                    title: "需要辅助功能权限，平滑滚动才能生效。",
                    detail: "授权后才会接管鼠标滚轮；与剪贴板敲入、鼠标按键映射共用这一项权限。",
                    onRecheck: {
                        app.refreshTrust()
                        scroll.refreshPermission()
                    }
                )
            }

            statusCard
            effectCard
            tryCard
            advancedCard
            tipsCard
        }
        .onAppear {
            app.refreshTrust()
            scroll.refreshPermission()
        }
    }

    // MARK: - 状态

    private var statusCard: some View {
        CardSurface {
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
                    if case .failed = scroll.tapState {
                        Button("重新启动") { scroll.restartTap() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Text("启用")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("启用平滑滚动")
                }
                .fixedSize()
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
        if !scroll.enabled { return "平滑滚动已关闭" }

        switch scroll.tapState {
        case .running: return "平滑滚动已启用"
        case .permissionDenied: return "等待辅助功能权限"
        case .failed: return "滚轮监听未启动"
        case .stopped: return "滚轮监听未启动"
        }
    }

    private var statusSubtitle: String {
        if !app.trusted { return "授权后才能接管鼠标滚轮" }
        if !scroll.enabled { return "滚轮保持系统原生行为" }

        switch scroll.tapState {
        case .running:
            return "已接管鼠标滚轮，触控板保持原生"
        case .permissionDenied:
            return "授权后才能接管鼠标滚轮"
        case .failed(let message):
            return message
        case .stopped:
            return "正在启动滚轮监听…"
        }
    }

    private var statusSubtitleColor: Color {
        if case .failed = scroll.tapState { return .red }
        return .secondary
    }

    private var statusColor: Color {
        if !app.trusted { return .orange }
        if !scroll.enabled { return .secondary }

        switch scroll.tapState {
        case .running: return Theme.green
        case .permissionDenied: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { scroll.enabled },
            set: { scroll.enabled = $0 }
        )
    }

    // MARK: - 滚动效果

    private var effectCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("滚动效果")
                    .font(.headline)

                SettingsRow(
                    "平滑滚动",
                    detail: "关闭后只在原事件上反向，不接管、不加倍率"
                ) {
                    Toggle("", isOn: smoothBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("平滑滚动")
                }

                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(leading: "平滑时长") {
                        Slider(value: durationBinding, in: 80...400, step: 20)
                            .accessibilityLabel("平滑时长")
                        Text("\(Int(scroll.durationMs))ms")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    SettingsRow(leading: "滚动倍率") {
                        Slider(value: gainBinding, in: 0.5...4.0, step: 0.1)
                            .accessibilityLabel("滚动倍率")
                        Text(String(format: "%.1f×", scroll.gain))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    SettingsRow(leading: "最高加速") {
                        Slider(value: accelerationMaxBinding, in: 1.5...10.0, step: 0.1)
                            .accessibilityLabel("最高加速")
                        Text(String(format: "%.1f×", scroll.accelerationMax))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!scroll.smooth)
                .opacity(scroll.smooth ? 1 : 0.45)

                Divider()

                SettingsRow("垂直方向反向") {
                    Toggle("", isOn: reverseVerticalBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("垂直方向反向")
                }

                SettingsRow("水平方向反向") {
                    Toggle("", isOn: reverseHorizontalBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("水平方向反向")
                }
            }
        }
    }

    private var smoothBinding: Binding<Bool> {
        Binding(get: { scroll.smooth }, set: { scroll.smooth = $0 })
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { scroll.durationMs },
            set: { scroll.durationMs = (($0 / 20).rounded() * 20) }
        )
    }

    private var gainBinding: Binding<Double> {
        Binding(
            get: { scroll.gain },
            set: { scroll.gain = (($0 * 10).rounded() / 10) }
        )
    }

    private var accelerationMaxBinding: Binding<Double> {
        Binding(
            get: { scroll.accelerationMax },
            set: { scroll.accelerationMax = (($0 * 10).rounded() / 10) }
        )
    }

    private var reverseVerticalBinding: Binding<Bool> {
        Binding(get: { scroll.reverseVertical }, set: { scroll.reverseVertical = $0 })
    }

    private var reverseHorizontalBinding: Binding<Bool> {
        Binding(get: { scroll.reverseHorizontal }, set: { scroll.reverseHorizontal = $0 })
    }

    // MARK: - 试一试

    private var tryCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("试一试")
                        .font(.headline)
                    Text("把指针放进下面的框里滚动鼠标滚轮，直接感受平滑和反向。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sampleLines.indices, id: \.self) { index in
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(sampleLines[index])
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            if index != sampleLines.indices.last {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel("滚轮试滚区域")
            }
        }
    }

    private let sampleLines = [
        "第一行 · 平滑滚动会把滚轮的一格摊开成一小段动画。",
        "第二行 · 滚得快的时候，目标会不断累加，动画不会断开。",
        "第三行 · 中途反向时目标直接拐弯，不会先停下再重来。",
        "第四行 · 触控板、Magic Mouse 和 ⌘+滚轮会原样放行。",
        "第五行 · 这一页本身也可以滚，指针放在框内即可对比。",
        "第六行 · 把平滑关掉，只保留反向，感受一下区别。",
        "第七行 · 时长越短越跟手，越长越柔和。",
        "第八行 · 倍率用来补偿不同鼠标一格的距离。",
        "第九行 · 有些驱动会把滚轮伪装成连续事件。",
        "第十行 · 那种事件会被当成触控板放行，不会平滑。",
        "第十一行 · 如果手感发飘，先检查有没有别的平滑工具在跑。",
        "第十二行 · 滚动到这里说明列表足够长了。",
    ]

    // MARK: - 高级参数

    private var advancedCard: some View {
        CardSurface {
            DisclosureRow(
                "高级参数",
                systemImage: "slider.horizontal.3",
                isExpanded: $scroll.advancedExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow("最近一次滚轮输入", detail: lastInputDetail) {
                        Button("恢复默认") { scroll.resetToDefaults() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("恢复平滑滚动的默认设置")
                    }

                    Divider()

                    Text("触控板、Magic Mouse 和 ⌘+滚轮（缩放）会被原样放行，不受这里的平滑与反向影响。Shift+滚轮按横向滚动处理，平滑和反向都生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lastInputDetail: String {
        guard let input = scroll.lastInput else {
            return "滚动一下鼠标滚轮，这里会显示原始点数、行数和目标进程"
        }

        var parts = [
            String(format: "垂直 %.0fpt · 水平 %.0fpt", input.dyPoints, input.dxPoints),
            "行 \(input.lineDeltaY)/\(input.lineDeltaX)",
        ]

        if input.captured {
            parts.append("已接管")
            if input.reversed { parts.append("已反向") }
            if input.boost > 1.01 {
                parts.append(String(format: "加速 %.1f× · 总 %.1f×", input.boost, input.boost * scroll.gain))
            }
        } else {
            parts.append("未接管（\(input.passthrough?.label ?? "放行")）")
        }

        parts.append("PID \(input.pid)")
        parts.append(input.date.formatted(date: .omitted, time: .standard))
        return parts.joined(separator: " · ")
    }

    // MARK: - 提示

    private var tipsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                tip(
                    icon: "exclamationmark.triangle",
                    text: Text("**别和 iScroll、Mos、罗技 Options 等平滑工具同时运行。** 两层平滑叠在一起会变成双重缓动，手感会发飘。先退出它们再试。"),
                    color: .orange
                )
                tip(
                    icon: "computermouse",
                    text: Text("**部分鼠标驱动会发送连续或带相位的事件。** 这类事件看起来像触控板，会被原样放行；如果滚轮完全没反应，先在驱动里关掉「平滑滚动」。")
                )
                tip(
                    icon: "magnifyingglass",
                    text: Text("**⌘+滚轮是系统缩放。** 带 ⌘ 的滚轮一律不接管，避免把缩放改成滚动。")
                )
            }
        }
    }

    private func tip(icon: String, text: Text, color: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            text
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

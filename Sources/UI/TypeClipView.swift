import SwiftUI

struct TypeClipView: View {
    @ObservedObject private var clip = TypeClipFeature.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        VStack(spacing: 12) {
            statusCard
            settingsCard
            advancedCard
            diagnosticsCard
        }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    IconTile(
                        systemName: clip.isActive ? "keyboard.badge.ellipsis" : "doc.on.clipboard",
                        color: phaseColor
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("剪贴板敲入")
                                .font(.system(size: 13.5, weight: .semibold))
                            Spacer(minLength: 4)
                            Badge(text: phaseLabel, color: phaseColor)
                        }

                        Text(clip.clipboardSummary)
                            .font(.caption2)
                            .foregroundStyle(clip.clipboardOK ? Color.secondary : Color.orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let line = clip.statusLine {
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(clip.phase == .failed ? Color.red : Color.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if clip.isActive, let value = clip.progress {
                    ProgressView(value: value)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                }

                if clip.isActive {
                    Button { clip.cancel() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "stop.fill")
                            Text("中断敲入")
                            Spacer()
                            Text("再按 ⌃⌘V").font(.caption2).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(FilledActionButtonStyle(color: .red))
                } else {
                    Button { clip.handleHotkey(enter: false) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "keyboard")
                            Text("敲入剪贴板")
                            Spacer()
                            HotkeyCaps(caps: ["⌃", "⌘", "V"], onFilled: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(FilledActionButtonStyle(color: Theme.accent))
                    .opacity(!clip.clipboardOK || !app.trusted ? 0.45 : 1)
                    .disabled(!clip.clipboardOK || !app.trusted)
                }

                Text("⌃⌘V 敲入 · ⌃⌘↩ 敲入并回车 · 敲入中再按一次中断")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
    }

    private var phaseLabel: String {
        switch clip.phase {
        case .idle: return "就绪"
        case .typing: return "敲入中"
        case .done: return "完成"
        case .aborted: return "已中断"
        case .failed: return "异常"
        }
    }

    private var phaseColor: Color {
        switch clip.phase {
        case .idle: return Theme.accent
        case .typing: return .orange
        case .done: return Theme.green
        case .aborted: return Color.gray
        case .failed: return .red
        }
    }

    // MARK: 基础设置

    private var settingsCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("敲入设置")

                VStack(alignment: .leading, spacing: 4) {
                    SettingSliderRow(
                        title: "速度",
                        value: Binding(get: { clip.paceMs }, set: { clip.paceMs = $0 }),
                        range: 50...500
                    )
                    Text(clip.manual ? effectiveDetail : clip.derivedDetail)
                        .font(.caption2)
                        .foregroundStyle(clip.manual ? Color.orange : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("输入法")
                            .font(.callout)
                            .frame(width: 62, alignment: .leading)
                        Picker("", selection: Binding(get: { clip.imeMode }, set: { clip.imeMode = $0 })) {
                            ForEach(IMEMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                    Text(clip.imeMode.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 70)
                }

                Divider().opacity(0.4)

                Toggle(isOn: Binding(get: { clip.pressEnterSuffix }, set: { clip.pressEnterSuffix = $0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("结尾按回车").font(.callout)
                        Text("敲入完成后补一个 Return，适合提交命令")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var effectiveDetail: String {
        let p = clip.effectiveRaw
        return "手动 · 间隔 \(Int(p.interval))ms · 按住 \(Int(p.hold))ms · 抖动 \(Int(p.jitter))ms · 修饰键 \(Int(p.modifierDelay))ms"
    }

    // MARK: 高级参数

    private var advancedCard: some View {
        PanelCard(padding: 12) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { clip.advancedExpanded },
                    set: { clip.advancedExpanded = $0 }
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { clip.manual }, set: { clip.manual = $0 })) {
                        Text("手动覆盖速度轴").font(.callout)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    let d = TypeClipFeature.derived(paceMs: clip.paceMs)
                    SettingSliderRow(
                        title: "字符间隔",
                        value: rawBinding(\.intervalMs, fallback: d.interval),
                        range: 50...500
                    )
                    .disabled(!clip.manual)
                    .opacity(clip.manual ? 1 : 0.5)

                    SettingSliderRow(
                        title: "按住时长",
                        value: rawBinding(\.holdMs, fallback: d.hold),
                        range: 20...150
                    )
                    .disabled(!clip.manual)
                    .opacity(clip.manual ? 1 : 0.5)

                    SettingSliderRow(
                        title: "随机抖动",
                        value: rawBinding(\.jitterMs, fallback: d.jitter),
                        range: 0...80
                    )
                    .disabled(!clip.manual)
                    .opacity(clip.manual ? 1 : 0.5)

                    SettingSliderRow(
                        title: "修饰键延迟",
                        value: rawBinding(\.modifierDelayMs, fallback: d.modifierDelay),
                        range: 0...200,
                        step: 10
                    )
                    .disabled(!clip.manual)
                    .opacity(clip.manual ? 1 : 0.5)

                    HStack(spacing: 6) {
                        Text(clip.manual
                             ? "拖动滑杆即使用手动参数；移动速度滑杆会自动退出。"
                             : "仅在速度轴与实测不符时用来排障。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if clip.manual {
                            Button("恢复自动") { clip.manual = false }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                    Text("高级参数").font(.caption)
                    if clip.manual {
                        Badge(text: "手动", color: .orange)
                    }
                    Spacer()
                }
                .foregroundStyle(clip.manual ? Color.orange : Color.secondary)
            }
        }
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

    // MARK: 诊断日志

    private var diagnosticsCard: some View {
        PanelCard(padding: 12) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { clip.diagnosticsExpanded },
                    set: { clip.diagnosticsExpanded = $0 }
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { clip.debugLog }, set: { clip.debugLog = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("记录逐字符注入路径").font(.callout)
                            Text("排查 # 退化成 3 这类问题时再打开")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    HStack(spacing: 8) {
                        Text("~/Library/Logs/MacExpert.log")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("打开日志") { AppLog.revealFile() }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }

                    Text(clip.debugLog
                         ? "打开后日志会含被敲入的字符明文（等于剪贴板内容），排查完请关掉"
                         : "关闭时日志只记配置与统计，不含剪贴板内容")
                        .font(.caption2)
                        .foregroundStyle(clip.debugLog ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                    Text("诊断日志").font(.caption)
                    Spacer()
                }
                .foregroundStyle(clip.debugLog ? Color.orange : Color.secondary)
            }
        }
    }
}

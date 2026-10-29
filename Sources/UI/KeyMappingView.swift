import AppKit
import Carbon
import SwiftUI

/// 主窗口里的「鼠标按键映射」页。
struct KeyMappingView: View {

    @ObservedObject private var mapping = KeyMappingFeature.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        PageScaffold {
            if !app.trusted {
                PermissionBanner(
                    title: "需要辅助功能权限，鼠标按键映射才能生效。",
                    detail: "授权后侧键才会被监听；与剪贴板敲入共用这一项权限。",
                    onRecheck: {
                        app.refreshTrust()
                        mapping.refreshPermission()
                    }
                )
            }

            statusCard
            mappingsCard
            advancedCard
            tipsCard
        }
        .onAppear {
            app.refreshTrust()
            mapping.refreshPermission()
        }
        .onDisappear {
            mapping.closeEditor()
            mapping.pendingDelete = nil
        }
        .sheet(item: $mapping.editorContext) { context in
            KeyMappingEditor(context: context)
        }
        .alert(
            "删除这条映射？",
            isPresented: Binding(
                get: { mapping.pendingDelete != nil },
                set: { if !$0 { mapping.pendingDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                mapping.pendingDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = mapping.pendingDelete {
                    mapping.delete(item.id)
                }
                mapping.pendingDelete = nil
            }
        } message: {
            Text("删除后，这个鼠标键会恢复系统默认行为。")
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
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if case .failed = mapping.tapState {
                        Button("重新启动") { mapping.restartTap() }
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
                        .accessibilityLabel("启用鼠标按键映射")
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
        if !mapping.enabled { return "鼠标按键映射已暂停" }
        if mapping.mappings.isEmpty { return "等待添加映射" }
        if mapping.activeCount == 0 { return "没有生效的映射" }

        switch mapping.tapState {
        case .running: return "鼠标按键映射已启用"
        case .permissionDenied: return "等待辅助功能权限"
        case .failed: return "鼠标监听未启动"
        case .stopped: return "鼠标监听未启动"
        }
    }

    private var statusSubtitle: String {
        if !app.trusted { return "授权后才会开始监听鼠标侧键" }
        if !mapping.enabled { return "侧键已恢复系统默认行为" }
        if mapping.mappings.isEmpty { return "添加第一条映射后开始监听" }
        if mapping.activeCount == 0 { return "打开任意一条映射后开始监听" }

        switch mapping.tapState {
        case .failed(let message):
            return message
        case .permissionDenied:
            return "授权后才会开始监听鼠标侧键"
        case .stopped:
            return "正在启动鼠标监听…"
        case .running:
            var text = "正在监听 \(mapping.activeCount) 条映射"
            if let last = mapping.lastTrigger {
                text += " · 最近：\(MouseButton.label(last.button)) → \(last.combo.displayText)（\(last.app)）"
            }
            return text
        }
    }

    private var statusColor: Color {
        if !app.trusted { return .orange }
        if !mapping.enabled { return .secondary }
        if mapping.mappings.isEmpty || mapping.activeCount == 0 { return .secondary }

        switch mapping.tapState {
        case .running: return Theme.green
        case .permissionDenied: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { mapping.enabled },
            set: { mapping.enabled = $0 }
        )
    }

    // MARK: - 映射列表

    private var mappingsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("映射")
                            .font(.headline)
                        Text("侧键松开后会发送你设定的快捷键，原来的行为会被拦截。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    if !mapping.mappings.isEmpty {
                        Button {
                            mapping.openEditor()
                        } label: {
                            Label("添加映射", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if mapping.mappings.isEmpty {
                    emptyState
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(mapping.mappings) { item in
                            mappingRow(item)
                            if item.id != mapping.mappings.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func mappingRow(_ item: KeyMapping) -> some View {
        HStack(spacing: 8) {
            Button {
                mapping.openEditor(mapping: item)
            } label: {
                HStack(spacing: 8) {
                    MouseButtonBadge(button: item.button)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    HotkeyCaps(caps: item.combo.displayCaps)

                    if !item.displayName.isEmpty {
                        Text(item.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(item.enabled ? 1 : 0.45)
            .accessibilityLabel(rowAccessibilityLabel(item))

            Toggle("", isOn: enabledBinding(for: item))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("启用映射：\(MouseButton.label(item.button)) 发送 \(item.combo.displayText)")

            Menu {
                Button("编辑…") {
                    mapping.openEditor(mapping: item)
                }
                Divider()
                Button("删除映射", role: .destructive) {
                    mapping.pendingDelete = item
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("\(MouseButton.label(item.button)) 的更多操作")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func enabledBinding(for item: KeyMapping) -> Binding<Bool> {
        Binding(
            get: { item.enabled },
            set: { mapping.setEnabled(id: item.id, $0) }
        )
    }

    private func rowAccessibilityLabel(_ item: KeyMapping) -> String {
        var text = "编辑映射：\(MouseButton.label(item.button)) 发送 \(item.combo.displayText)"
        if !item.displayName.isEmpty {
            text += "，\(item.displayName)"
        }
        return text
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "computermouse")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                )

            Text("把鼠标侧键变成快捷键")
                .font(.headline)
                .padding(.top, 12)

            Text("按一下侧键，就能发送复制、粘贴、切换桌面等组合键。原按键行为会被拦截。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 4)

            Button("添加第一条映射") {
                mapping.openEditor()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 14)

            VStack(spacing: 6) {
                presetRow(button: 3, combo: KeyMappingPresets.back, name: "后退")
                presetRow(button: 4, combo: KeyMappingPresets.forward, name: "前进")
                presetRow(button: 2, combo: KeyMappingPresets.typeClip, name: "敲入剪贴板")
            }
            .frame(maxWidth: 420)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func presetRow(button: Int, combo: KeyCombo, name: String) -> some View {
        Button {
            mapping.openEditor(
                preset: KeyMapping(
                    id: UUID(),
                    button: button,
                    combo: combo,
                    name: name,
                    enabled: true
                )
            )
        } label: {
            HStack(spacing: 8) {
                MouseButtonBadge(button: button)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                HotkeyCaps(caps: combo.displayCaps)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 高级与诊断

    private var advancedCard: some View {
        CardSurface {
            DisclosureRow(
                "高级与诊断",
                systemImage: "slider.horizontal.3",
                isExpanded: $mapping.advancedExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(leading: "发送间隔") {
                        Slider(value: sendDelayBinding, in: 0...200, step: 10)
                        Text("\(Int(mapping.sendDelayMs))ms")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }

                    Divider()

                    SettingsRow("按键探测", detail: detectedDetail) {
                        Button("重新启动监听") {
                            mapping.restartTap()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text("触发记录只保留在内存（最多 20 条），不写入日志。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if !mapping.recentEvents.isEmpty {
                            Text("本次运行 \(mapping.recentEvents.count) 次")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var sendDelayBinding: Binding<Double> {
        Binding(
            get: { mapping.sendDelayMs },
            set: { mapping.sendDelayMs = min(max($0, 0), 200) }
        )
    }

    private var detectedDetail: String {
        guard let event = mapping.lastDetected else {
            return "按一下鼠标侧键，这里会显示系统编号"
        }
        let time = event.date.formatted(date: .omitted, time: .standard)
        let suffix = event.mapped ? " · 已映射" : ""
        return "按钮 \(event.button) · \(event.app) · \(time)\(suffix)"
    }

    // MARK: - 提示

    private var tipsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                tip(
                    icon: "lightbulb",
                    text: Text("**厂商驱动可能先截走侧键。** 如果按侧键没反应，先在罗技 Options+、雷蛇 Synapse 等驱动里把它设为「无操作」。")
                )
                tip(
                    icon: "computermouse",
                    text: Text("**少数鼠标的侧键发送的是键盘事件。** 这种键不会出现在鼠标监听里，无法映射。")
                )
                if hasArrowSpaceMapping {
                    tip(
                        icon: "arrow.left.arrow.right",
                        text: Text("**⌃← / ⌃→ 依赖系统里的「左/右切换桌面」快捷键。** 如果你改过系统快捷键，映射也要改成相同的组合。")
                    )
                }
            }
        }
    }

    /// 命中切桌面组合时，提醒映射要和系统快捷键保持一致。
    private var hasArrowSpaceMapping: Bool {
        mapping.mappings.contains { item in
            item.enabled
                && item.combo.modifiers == [.control]
                && (item.combo.keyCode == UInt16(kVK_LeftArrow) || item.combo.keyCode == UInt16(kVK_RightArrow))
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

// MARK: - 鼠标按键小标签

struct MouseButtonBadge: View {
    let button: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "computermouse")
                .font(.system(size: 10.5, weight: .medium))
            Text(MouseButton.label(button))
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        )
        .help(MouseButton.hint(button))
        .fixedSize()
    }
}

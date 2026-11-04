import AppKit
import SwiftUI

/// 添加/编辑映射的弹窗。鼠标键可以点选，也可以点捕获后直接按一下；
/// 快捷键用本地键盘监听录制，录制期间按键不会传给应用。
struct KeyMappingEditor: View {

    let context: KeyMappingEditorContext
    @ObservedObject private var model: KeyMappingEditorModel
    @Environment(\.dismiss) private var dismiss

    init(context: KeyMappingEditorContext) {
        self.context = context
        self._model = ObservedObject(wrappedValue: context.model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                formCard

                if !model.errors.isEmpty {
                    warning
                }

                summary
            }
            .padding(20)

            Divider()
            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Theme.accent)
        .onDisappear {
            model.cancel()
        }
        .alert("要删除这条映射吗？", isPresented: $model.showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                model.feature.delete(model.id)
                dismiss()
            }
        } message: {
            Text("删除后，这个鼠标键会恢复系统默认行为。")
        }
    }

    // MARK: - 标题栏

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.title)
                .font(.title3.weight(.semibold))
            Text("选择鼠标按键并录制要触发的键盘快捷键")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 表单

    private var formCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 0) {
                mouseButtonSection
                Divider()
                    .padding(.vertical, 12)
                shortcutSection
                Divider()
                    .padding(.vertical, 12)
                nameSection
            }
        }
    }

    // MARK: - 鼠标按键

    private var mouseButtonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("鼠标按键")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("鼠标按键", selection: $model.button) {
                    ForEach([2, 3, 4, 5], id: \.self) { button in
                        Text(MouseButton.label(button)).tag(button)
                    }
                    if ![2, 3, 4, 5].contains(model.button) {
                        Text(MouseButton.label(model.button)).tag(model.button)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button {
                    model.toggleButtonCapture()
                } label: {
                    if model.isCapturingButton {
                        Text("正在识别…")
                    } else {
                        Label("按键识别", systemImage: "computermouse")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(model.isCapturingButton ? "取消按键识别" : "按鼠标键自动识别")
            }

            if model.isCapturingButton {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("请按一下你要映射的鼠标侧键或中键…")
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button("取消") {
                        model.stopButtonCapture()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.40), lineWidth: 1)
                )
            }

            Text(model.buttonHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = model.captureError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 快捷键

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("触发快捷键")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.toggleShortcutRecording()
            } label: {
                HStack(spacing: 8) {
                    if model.isRecordingShortcut {
                        ProgressView()
                            .controlSize(.small)
                        Text("请按下快捷键…")
                        Spacer()
                        Text("点击取消")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let combo = model.combo {
                        HotkeyCaps(caps: combo.displayCaps)
                        Spacer()
                        Text("点击重新录制")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                        Text("点击录制快捷键")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            model.isRecordingShortcut ? Theme.accent : Color.primary.opacity(0.10),
                            lineWidth: model.isRecordingShortcut ? 1.5 : 1
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("录制时会拦截这次按键，包括 ⌃← / ⌃→ 这类系统快捷键。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 名称

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名称（可选）")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("留空自动使用快捷键名称，如「复制」", text: $model.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - 警告与摘要

    private var warning: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.errors.enumerated()), id: \.offset) { _, error in
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var summary: some View {
        HStack(spacing: 8) {
            MouseButtonBadge(button: model.button)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            if let combo = model.combo {
                HotkeyCaps(caps: combo.displayCaps)
                if !model.summaryName.isEmpty {
                    Text(model.summaryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("还没有选择快捷键")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - 底部操作栏

    private var footer: some View {
        HStack(spacing: 10) {
            if !model.isNew {
                Button(role: .destructive) {
                    model.showDeleteConfirm = true
                } label: {
                    Label("删除…", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }

            Spacer(minLength: 12)

            Button("取消") {
                model.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("保存") {
                guard let mapping = model.buildMapping() else { return }
                model.feature.finishEditor(context: context, mapping: mapping)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

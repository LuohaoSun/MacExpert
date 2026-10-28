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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    triggerSection
                    shortcutSection
                    nameSection

                    if !model.errors.isEmpty {
                        warning
                    }

                    summary

                    if !model.isNew {
                        deleteButton
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520)
        .frame(minHeight: 560, maxHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            model.cancel()
        }
        .alert("删除这条映射？", isPresented: $model.showDeleteConfirm) {
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
        ZStack {
            Text(model.title)
                .font(.headline)

            HStack {
                Button("取消") {
                    model.cancel()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                Button("保存") {
                    guard let mapping = model.buildMapping() else { return }
                    model.feature.finishEditor(context: context, mapping: mapping)
                    dismiss()
                }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(model.canSave ? Color.accentColor : Color.secondary)
                .disabled(!model.canSave)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: - 鼠标按键

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("鼠标按键")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.toggleButtonCapture()
            } label: {
                HStack(spacing: 8) {
                    if model.isCapturingButton {
                        ProgressView()
                            .controlSize(.small)
                        Text("请按一下鼠标侧键…")
                        Spacer()
                        Text("点击取消")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "computermouse")
                            .foregroundStyle(.secondary)
                        Text(MouseButton.label(model.button))
                            .fontWeight(.medium)
                        Spacer()
                        Text("点击后按下鼠标侧键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            model.isCapturingButton ? Theme.accent : Color.primary.opacity(0.10),
                            lineWidth: model.isCapturingButton ? 1.5 : 1
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
            Text("发送快捷键")
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
                        Text("还没有选择快捷键")
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("点击录制")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
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

            TextField("例如：复制", text: $model.name)
                .textFieldStyle(.roundedBorder)

            Text("留空会自动使用常见组合名。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.showDeleteConfirm = true
        } label: {
            Label("删除这条映射", systemImage: "trash")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }
}

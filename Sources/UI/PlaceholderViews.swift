import SwiftUI

// MARK: - 按键映射（界面原型）

struct KeyMappingPrototypeView: View {
    var body: some View {
        VStack(spacing: 12) {
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        IconTile(systemName: "computermouse", color: Theme.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("鼠标按键映射")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Badge(text: "规划中", color: Theme.purple)
                            }
                            Text("侧键、中键 → 任意键盘组合键")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text("把鼠标侧键映射成复制、粘贴、切换应用等键盘组合键。触发方式计划支持单击、双击与长按。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PanelCard(padding: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle("界面预览 · 尚未生效")
                        .padding(.bottom, 10)
                    MappingRow(mouse: "侧键 4", action: ["⌘", "C"], name: "复制")
                    RowDivider()
                    MappingRow(mouse: "侧键 5", action: ["⌘", "V"], name: "粘贴")
                    RowDivider()
                    MappingRow(mouse: "中键", action: ["⌃", "⌘", "V"], name: "敲入剪贴板")
                }
            }

            PanelCard(padding: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.purple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("实现方式")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("全局监听鼠标事件并合成键盘事件，与「剪贴板敲入」共用辅助功能权限。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct MappingRow: View {
    let mouse: String
    let action: [String]
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "computermouse")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(mouse).font(.caption)
            }
            .frame(width: 78, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            HotkeyCaps(caps: action)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)
            Badge(text: "示例", color: Color.gray)
        }
        .padding(.vertical, 8)
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider().opacity(0.4)
    }
}

// MARK: - 热键翻译（界面原型）

struct TranslatePrototypeView: View {
    var body: some View {
        VStack(spacing: 12) {
            PanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        IconTile(systemName: "character.bubble", color: Theme.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("热键翻译")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Badge(text: "规划中", color: Theme.teal)
                            }
                            Text("选中文本 → 热键 → 译文浮层")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text("在任意应用里选中文字，按一下热键就能看到译文，不打断当前工作流。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PanelCard(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("界面预览 · 尚未生效")
                    HStack {
                        Text("Good morning")
                            .font(.system(size: 13, design: .serif))
                        Spacer()
                        Badge(text: "自动 → 中文", color: Theme.teal)
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("早上好")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        HotkeyCaps(caps: ["⌥", "D"])
                        Text("选中文本后按下，译文以浮层显示")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PanelCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("计划中的能力")
                    roadmapRow(icon: "text.cursor", text: "划词翻译：选中即译，不打断当前应用")
                    roadmapRow(icon: "camera.viewfinder", text: "截图 OCR：框选图片里的文字再翻译")
                    roadmapRow(icon: "keyboard", text: "译文回填：接 TypeClip，把译文直接敲进远程桌面")
                }
            }
        }
    }

    private func roadmapRow(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.teal)
                .frame(width: 14)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

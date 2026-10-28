import AppKit
import SwiftUI

// MARK: - 按键映射（界面原型）

struct KeyMappingPrototypeView: View {
    var body: some View {
        PageScaffold {
            CardSurface {
                VStack(alignment: .leading, spacing: 7) {
                    Text("按键映射")
                        .font(.headline)
                    Text("把鼠标侧键映射成复制、粘贴、切换应用等键盘组合键。触发方式计划支持单击、双击与长按。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            CardSurface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("界面预览")
                            .font(.headline)
                        Spacer()
                        Text("尚未生效")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    mappingRow(mouse: "侧键 4", action: ["⌘", "C"], name: "复制")
                    Divider()
                    mappingRow(mouse: "侧键 5", action: ["⌘", "V"], name: "粘贴")
                    Divider()
                    mappingRow(mouse: "中键", action: ["⌃", "⌘", "V"], name: "敲入剪贴板")
                }
            }

            CardSurface {
                VStack(alignment: .leading, spacing: 6) {
                    Text("实现方式")
                        .font(.headline)
                    Text("全局监听鼠标事件并合成键盘事件，与「剪贴板敲入」共用辅助功能权限。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func mappingRow(mouse: String, action: [String], name: String) -> some View {
        HStack(spacing: 8) {
            Text(mouse)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            HotkeyCaps(caps: action)
            Text(name)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - 热键翻译（界面原型）

struct TranslatePrototypeView: View {
    var body: some View {
        PageScaffold {
            CardSurface {
                VStack(alignment: .leading, spacing: 7) {
                    Text("热键翻译")
                        .font(.headline)
                    Text("在任意应用里选中文字，按一下热键就能看到译文，不打断当前工作流。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            CardSurface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("界面预览")
                            .font(.headline)
                        Spacer()
                        Text("尚未生效")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    HStack {
                        Text("Good morning")
                            .font(.body)
                        Spacer()
                        Text("早上好")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("热键")
                            .foregroundStyle(.secondary)
                        Spacer()
                        HotkeyCaps(caps: ["⌥", "D"])
                    }
                }
            }

            CardSurface {
                VStack(alignment: .leading, spacing: 8) {
                    Text("计划中的能力")
                        .font(.headline)
                    roadmapRow(icon: "text.cursor", text: "划词翻译：选中即译，不打断当前应用")
                    roadmapRow(icon: "camera.viewfinder", text: "截图 OCR：框选图片里的文字再翻译")
                    roadmapRow(icon: "keyboard", text: "译文回填：接 TypeClip，把译文直接敲进远程桌面")
                }
            }
        }
    }

    private func roadmapRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import AppKit
import SwiftUI

/// 菜单栏原生菜单：状态、剪贴板摘要、敲入动作和主窗口入口。
/// 不再使用自绘 popover，菜单项和快捷键都由系统渲染。
struct MenuBarMenu: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var clip = TypeClipFeature.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
            .onAppear {
                MainWindowController.shared.register(openWindow)
                app.refreshTrust()
                clip.refreshPasteboard()
            }
        Text(summaryLine)

        if !app.trusted {
            Button("去授权…") { Permissions.requestAccess() }
        }

        Divider()

        if clip.isActive {
            Button("中断敲入") { clip.cancel() }
                .keyboardShortcut("v", modifiers: [.control, .command])
        } else {
            Button("敲入剪贴板") { clip.handleHotkey(enter: false) }
                .keyboardShortcut("v", modifiers: [.control, .command])
                .disabled(!clip.clipboardOK || !app.trusted)

            Button("敲入并回车") { clip.handleHotkey(enter: true) }
                .keyboardShortcut(.return, modifiers: [.control, .command])
                .disabled(!clip.clipboardOK || !app.trusted)
        }

        Divider()

        Button("打开主窗口") { openMainWindow() }
            .keyboardShortcut("0", modifiers: .command)
        Button("设置…") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("退出 MacExpert") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var statusLine: String {
        if clip.isActive, let line = FeatureRegistry.statusLine() { return line }
        if clip.isActive { return "正在敲入…" }
        if !app.trusted { return "需要辅助功能权限" }
        if !clip.clipboardOK { return "剪贴板没有文本" }
        return "就绪 · 常驻菜单栏"
    }

    private var summaryLine: String {
        guard clip.clipboardOK else { return "剪贴板为空" }
        let oneLine = clip.clipboardSummary.replacingOccurrences(of: "\n", with: " ")
        let text = oneLine.count > 42 ? String(oneLine.prefix(42)) + "…" : oneLine
        return "剪贴板：\(text)"
    }

    private func openMainWindow() {
        MainWindowController.shared.show()
    }

    private func openSettings() {
        app.openSettings()
        MainWindowController.shared.show()
    }
}

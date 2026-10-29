import AppKit
import ApplicationServices
import SwiftUI

/// 菜单栏原生菜单：只保留打开主窗口、模块开关和退出。
/// 状态、剪贴板摘要和敲入动作都放在主窗口里，菜单保持最小。
struct MenuBarMenu: View {
    @ObservedObject private var clip = TypeClipFeature.shared
    @ObservedObject private var mapping = KeyMappingFeature.shared
    @ObservedObject private var scroll = SmoothScrollFeature.shared
    @ObservedObject private var translation = TranslationFeature.shared
    @ObservedObject private var monitor = MonitorFeature.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开主窗口") { openMainWindow() }
            .keyboardShortcut("0", modifiers: .command)
            .onAppear {
                MainWindowController.shared.register(openWindow)
            }

        Divider()

        Toggle("启用剪贴板敲入", isOn: clipEnabledBinding)

        if !mapping.mappings.isEmpty {
            Toggle("启用鼠标按键映射", isOn: mappingEnabledBinding)
        }

        Toggle("启用平滑滚动", isOn: smoothEnabledBinding)
        Toggle("启用热键翻译", isOn: translationEnabledBinding)
        Toggle("启用系统监控", isOn: monitorEnabledBinding)

        Divider()

        Button("退出 MacExpert") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var clipEnabledBinding: Binding<Bool> {
        Binding(
            get: { clip.enabled },
            set: { newValue in
                clip.enabled = newValue
                if newValue, !AXIsProcessTrusted() { Permissions.requestAccess() }
            }
        )
    }

    private var mappingEnabledBinding: Binding<Bool> {
        Binding(
            get: { mapping.enabled },
            set: { newValue in
                mapping.enabled = newValue
                if newValue, !AXIsProcessTrusted() { Permissions.requestAccess() }
            }
        )
    }

    private var smoothEnabledBinding: Binding<Bool> {
        Binding(
            get: { scroll.enabled },
            set: { newValue in
                scroll.enabled = newValue
                if newValue, !AXIsProcessTrusted() { Permissions.requestAccess() }
            }
        )
    }

    /// 翻译只用全局热键，不需要辅助功能权限，所以这里不弹授权。
    private var translationEnabledBinding: Binding<Bool> {
        Binding(
            get: { translation.enabled },
            set: { translation.enabled = $0 }
        )
    }

    /// 系统监控只读系统计数器，同样不需要辅助功能权限。
    private var monitorEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.enabled },
            set: { monitor.enabled = $0 }
        )
    }

    private func openMainWindow() {
        MainWindowController.shared.show()
    }
}

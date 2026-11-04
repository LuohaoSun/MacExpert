import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var clip = TypeClipFeature.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared

    var body: some View {
        PageScaffold {
            permissionCard
            if !hotkeys.failures.isEmpty {
                hotkeyFailuresCard
            }
            generalCard
            logCard
            aboutCard
        }
    }

    // MARK: - 权限

    private var permissionCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("权限")
                    .font(.headline)

                HStack(spacing: 8) {
                    Circle()
                        .fill(app.trusted ? Theme.green : Color.orange)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(app.trusted ? "辅助功能权限已开启" : "需要辅助功能权限")
                }

                Text(app.trusted
                     ? "剪贴板敲入、鼠标按键映射与平滑滚动共用此权限。"
                     : "请在「系统设置 > 隐私与安全性 > 辅助功能」中允许 MacExpert。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if app.trusted {
                        Button("打开系统设置") { Permissions.requestAccess() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("打开系统设置") { Permissions.requestAccess() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("重新检查") { app.refreshTrust() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 热键注册失败

    private var hotkeyFailuresCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷键冲突")
                    .font(.headline)

                ForEach(hotkeys.failures) { failure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(failure.name)
                            .font(.callout)
                        Spacer(minLength: 12)
                        Text(failure.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Text("以上快捷键已被其他应用占用，关闭冲突应用或修改其快捷键后即可恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 通用

    private var generalCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("通用")
                    .font(.headline)

                SettingsRow("开机自动启动", detail: "登录系统后自动在菜单栏运行") {
                    Toggle("", isOn: loginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if let error = app.loginError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - 日志

    private var logCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("日志")
                    .font(.headline)

                LogPathRow(
                    status: clip.debugLog ? "包含剪贴板文字" : "仅记录运行状态，不含剪贴板内容",
                    statusColor: clip.debugLog ? Color.orange : Color.secondary,
                    openTitle: "在 Finder 中显示",
                    showsFolderButton: true
                )
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        CardSurface {
            HStack(spacing: 12) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacExpert")
                        .font(.headline)
                    Text("版本 \(app.version) · 原生 macOS 效率工具箱")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("打开主窗口时显示 Dock 图标与应用菜单；关闭窗口后自动回到菜单栏静默运行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)

                Button {
                    UpdateChecker.shared.checkInteractively()
                } label: {
                    Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { app.loginEnabled }, set: { app.setLogin($0) })
    }
}

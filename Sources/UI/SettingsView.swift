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
                        .fill(app.trusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(app.trusted ? "辅助功能已授权" : "尚未获得辅助功能权限")
                    Text(app.trusted ? "辅助功能已授权" : "尚未获得辅助功能权限")
                }

                Text(app.trusted
                     ? "敲入与按键映射共用这一项权限。"
                     : "系统设置 → 隐私与安全性 → 辅助功能")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if app.trusted {
                        Button("打开系统设置") { Permissions.requestAccess() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("去授权") { Permissions.requestAccess() }
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
                Text("热键未能注册")
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

                Text("不影响功能本身是否可用；可在系统设置的键盘快捷键里检查冲突。")
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

                SettingsRow("开机自启", detail: "登录后自动驻留菜单栏") {
                    Toggle("", isOn: loginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if let error = app.loginError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Text("主窗口打开时会显示 Dock 图标和 App 菜单；关闭窗口后回到纯菜单栏状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    status: clip.debugLog ? "含字符明文" : "不含剪贴板内容",
                    statusColor: clip.debugLog ? Color.orange : Color.secondary,
                    openTitle: "打开日志",
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
                    Text("版本 \(app.version) · 自用 Mac 小工具集")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("后续新增的小工具会继续加到这个窗口里，不需要再单独做菜单栏应用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { app.loginEnabled }, set: { app.setLogin($0) })
    }
}

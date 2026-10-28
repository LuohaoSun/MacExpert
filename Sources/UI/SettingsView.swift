import SwiftUI

struct SettingsView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var clip = TypeClipFeature.shared

    var body: some View {
        VStack(spacing: 12) {
            permissionCard
            generalCard
            logCard
            aboutCard
        }
    }

    // MARK: 权限

    private var permissionCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("权限")
                HStack(spacing: 10) {
                    IconTile(
                        systemName: app.trusted ? "checkmark.shield.fill" : "hand.raised.fill",
                        color: app.trusted ? Theme.green : .orange
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.trusted ? "辅助功能权限已开启" : "尚未获得辅助功能权限")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(app.trusted
                             ? "敲入与按键映射共用这一项权限"
                             : "系统设置 → 隐私与安全性 → 辅助功能")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button(app.trusted ? "打开系统设置" : "去授权") {
                        Permissions.requestAccess()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: 通用

    private var generalCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("通用")
                Toggle(isOn: Binding(get: { app.loginEnabled }, set: { app.setLogin($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("开机自启").font(.callout)
                        Text("登录后自动驻留菜单栏")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if let error = app.loginError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }

                Text("MacExpert 不显示 Dock 图标，所有功能都从菜单栏图标进入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 日志

    private var logCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 9) {
                CardTitle("日志")
                Text("~/Library/Logs/MacExpert.log")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 12) {
                    Button("打开日志") { AppLog.revealFile() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Button("打开文件夹") { AppLog.revealFolder() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 4)
                    Text(clip.debugLog ? "含字符明文" : "不含剪贴板内容")
                        .font(.caption2)
                        .foregroundStyle(clip.debugLog ? Color.orange : Color.secondary)
                }
            }
        }
    }

    // MARK: 关于

    private var aboutCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.brandGradient)
                        Image(systemName: "command")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("MacExpert")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("版本 \(app.version) · 自用 Mac 小工具集")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider().opacity(0.4)

                HStack(spacing: 6) {
                    Badge(text: "剪贴板敲入", color: Theme.green)
                    Badge(text: "按键映射", color: Color.gray)
                    Badge(text: "热键翻译", color: Color.gray)
                    Spacer(minLength: 0)
                }

                Text("后续新增的小工具会继续加到这个面板里，不需要再单独做菜单栏应用。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

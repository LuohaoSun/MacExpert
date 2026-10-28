import SwiftUI

// MARK: - 页面脚手架

/// 主窗口各页的统一外框：纵向滚动、定宽内容列与一致留白。
/// 背景保持透明，露出系统窗口灰，不再画自定义标题栏。
struct PageScaffold<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

// MARK: - 设置行

/// 设置项通用行：左边标题（可带说明），右边控件。
/// `leading` 初始化器用于滑杆、菜单这类需要固定标题宽度的行。
struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let leadingWidth: CGFloat?
    let trailing: Trailing

    /// 普通模式：标题 + 可选说明在左，控件在右。
    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.leadingWidth = nil
        self.trailing = trailing()
    }

    /// leading 模式：标题固定宽度，右侧控件自行占满剩余空间。
    init(
        leading title: String,
        width: CGFloat = 80,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = nil
        self.leadingWidth = width
        self.trailing = trailing()
    }

    var body: some View {
        if let leadingWidth {
            HStack(spacing: 10) {
                Text(title)
                    .frame(width: leadingWidth, alignment: .leading)
                trailing
            }
        } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
        }
    }
}

// MARK: - 权限提示

/// 橙色权限提示条：说明 + 去授权 / 重新检查。
struct PermissionBanner: View {
    var title: String
    var detail: String?
    var onGrant: () -> Void
    var onRecheck: () -> Void

    init(
        title: String,
        detail: String? = nil,
        onGrant: @escaping () -> Void = { Permissions.requestAccess() },
        onRecheck: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.onGrant = onGrant
        self.onRecheck = onRecheck
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button("去授权", action: onGrant)
                .buttonStyle(.borderedProminent)
            Button("重新检查", action: onRecheck)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }
}

// MARK: - 日志路径

/// 日志路径行：路径 + 可选状态文字，按需给出「打开」或「打开 + 打开文件夹」按钮。
struct LogPathRow: View {
    var path: String = "~/Library/Logs/MacExpert.log"
    var status: String? = nil
    var statusColor: Color = .secondary
    var openTitle: String = "打开"
    var showsFolderButton: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                if !showsFolderButton {
                    Button(openTitle) { AppLog.revealFile() }
                        .buttonStyle(.bordered)
                }
            }

            if showsFolderButton {
                HStack(spacing: 10) {
                    Button(openTitle) { AppLog.revealFile() }
                        .buttonStyle(.bordered)
                    Button("打开文件夹") { AppLog.revealFolder() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

import AppKit
import Combine
import SwiftUI

// MARK: - 主面板

struct RootPanel: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var clip = TypeClipFeature.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            if !app.trusted {
                PermissionBanner()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            tabBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            Divider().opacity(0.5)

            if RuntimeFlags.isRenderingPreview {
                // ImageRenderer 不会渲染 ScrollView 里的内容，预览时直接展开整页。
                routeContent
            } else {
                ScrollView {
                    routeContent
                }
                .frame(height: Theme.contentHeight)
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: Theme.panelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if !RuntimeFlags.isRenderingPreview {
                app.refreshTrust()
                clip.refreshPasteboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !RuntimeFlags.isRenderingPreview else { return }
            app.refreshTrust()
            clip.refreshPasteboard()
        }
    }

    // MARK: 路由

    @ViewBuilder
    private var routeContent: some View {
        Group {
            if app.showingSettings {
                SettingsView()
            } else {
                switch app.selectedFeature {
                case .typeClip:
                    TypeClipView()
                case .keyMapping:
                    KeyMappingPrototypeView()
                case .translate:
                    TranslatePrototypeView()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                Image(systemName: "command")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: Theme.accent.opacity(0.22), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacExpert")
                    .font(.system(size: 14.5, weight: .semibold))
                HStack(spacing: 5) {
                    StatusDot(color: headerDotColor)
                    Text(headerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { app.toggleSettings() } label: {
                Image(systemName: app.showingSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.showingSettings ? Theme.accent : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(
                            app.showingSettings ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.05)
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(app.showingSettings ? "返回功能页" : "设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        if clip.isActive { return "正在敲入…" }
        if !app.trusted { return "缺少辅助功能权限" }
        return "就绪 · 常驻菜单栏"
    }

    private var headerDotColor: Color {
        if clip.isActive { return .orange }
        return app.trusted ? Theme.green : .orange
    }

    // MARK: 页签

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Feature.allCases) { feature in
                FeatureTabButton(
                    feature: feature,
                    selected: !app.showingSettings && app.selectedFeature == feature
                ) {
                    app.open(feature)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            StatusDot(color: footerDotColor)
            Text(footerText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("退出 MacExpert")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.02))
    }

    private var footerText: String {
        if clip.isActive { return "敲入中 · 再按 ⌃⌘V 中断" }
        if app.showingSettings { return "设置" }
        switch app.selectedFeature {
        case .typeClip:
            return app.trusted ? "⌃⌘V 敲入 · ⌃⌘↩ 敲入并回车" : "缺少辅助功能权限"
        case .keyMapping, .translate:
            return "界面原型 · 尚未上线"
        }
    }

    private var footerDotColor: Color {
        if clip.isActive { return .orange }
        if app.showingSettings { return app.trusted ? Theme.green : .orange }
        switch app.selectedFeature {
        case .typeClip:
            return app.trusted ? Theme.green : .orange
        case .keyMapping:
            return Theme.purple
        case .translate:
            return Theme.teal
        }
    }
}

// MARK: - 页签按钮

private struct FeatureTabButton: View {
    let feature: Feature
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: feature.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(feature.tabTitle)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.5)
            .foregroundStyle(selected ? Theme.accent : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(feature.title + (feature.isAvailable ? "" : "（界面原型，尚未上线）"))
    }
}

// MARK: - 权限提示

private struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("需要辅助功能权限")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("授权后才能模拟键盘")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去授权") { Permissions.requestAccess() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}

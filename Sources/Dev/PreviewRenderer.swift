#if MACEXPERT_DEV_HOOKS
import AppKit
import SwiftUI

/// 开发预览：把每个页签在浅色/深色下渲染成 PNG，方便在没有屏幕录制权限的情况下检查布局。
/// 只在 dev 构建中存在，release 构建里整块编掉。
@MainActor
enum PreviewRenderer {

    private struct Scene {
        let name: String
        let feature: Feature?
        let settings: Bool
        var advanced: Bool = false
    }

    /// borderless 窗口默认不能成为 key window，控件会画成非激活样式。
    private final class PreviewWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    static func renderAll(to directory: String) {
        RuntimeFlags.isRenderingPreview = true
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // 预览里用示例剪贴板内容，避免把真实剪贴板写进截图。
        TypeClipFeature.shared.clipboardSummary = "示例文本：把这段文字逐键敲入远程桌面 · 28 字符"
        TypeClipFeature.shared.clipboardOK = true
        // 预览展示「已授权」的完成态，权限横幅与禁用态不进入设计稿。
        AppState.shared.trusted = true

        let scenes = [
            Scene(name: "01-typeclip", feature: .typeClip, settings: false),
            Scene(name: "02-keymapping", feature: .keyMapping, settings: false),
            Scene(name: "03-translate", feature: .translate, settings: false),
            Scene(name: "04-settings", feature: nil, settings: true),
            Scene(name: "05-typeclip-expanded", feature: .typeClip, settings: false, advanced: true),
        ]

        for scene in scenes {
            AppState.shared.showingSettings = scene.settings
            if let feature = scene.feature {
                AppState.shared.selectedFeature = feature
            }
            TypeClipFeature.shared.advancedExpanded = scene.advanced
            TypeClipFeature.shared.diagnosticsExpanded = scene.advanced

            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let file = url.appendingPathComponent("\(scene.name)-\(suffix).png")
                render(scheme: scheme, to: file)
            }
        }

        print("preview written to \(directory)")
        fflush(stdout)
    }

    private static func render(scheme: ColorScheme, to url: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        NSApp.appearance = appearance

        let root = RootPanel()
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .key)
            .frame(width: Theme.panelWidth)

        // ImageRenderer 会把 Slider / Picker / Toggle 画成占位符，也没法渲染 ScrollView，
        // 所以这里用离屏 NSWindow + NSHostingView 走真实控件渲染路径。
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 760)

        let window = PreviewWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        window.makeKey()
        print("preview window key=\(window.isKeyWindow) appActive=\(NSApp.isActive)")

        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        let height = fit.height > 120 ? fit.height : 760
        hosting.frame = NSRect(x: 0, y: 0, width: Theme.panelWidth, height: height)
        window.setContentSize(NSSize(width: Theme.panelWidth, height: height))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("preview failed (no rep): \(url.path)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh) @ \(Int(height))pt")
        fflush(stdout)
    }
}
#endif

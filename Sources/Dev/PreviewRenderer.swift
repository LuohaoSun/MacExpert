#if MACEXPERT_DEV_HOOKS
import AppKit
import SwiftUI

/// 开发预览：把菜单栏面板和主窗口各页渲染成 PNG。
/// 只在 dev 构建中存在，release 构建里整块编掉。
@MainActor
enum PreviewRenderer {

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
        AppState.shared.trusted = true

        // 1. 主窗口各页：跟着 Feature.allCases 走，新增功能会自动多一张截图。
        let firstWindowNumber = 3
        var scenes: [(String, MainSection)] = Feature.allCases.enumerated().map { offset, feature in
            let number = String(format: "%02d", firstWindowNumber + offset)
            return ("\(number)-window-\(feature.rawValue)", .feature(feature))
        }
        let settingsNumber = firstWindowNumber + scenes.count
        scenes.append((String(format: "%02d-window-settings", settingsNumber), .settings))

        for (name, section) in scenes {
            AppState.shared.section = section
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                render(
                    MainWindowView(),
                    width: 1000,
                    height: 720,
                    scheme: scheme,
                    to: url.appendingPathComponent("\(name)-\(suffix).png")
                )
            }
        }

        // 4. 高级参数与诊断日志全部展开
        let expandedNumber = settingsNumber + 1
        AppState.shared.section = .feature(.typeClip)
        TypeClipFeature.shared.advancedExpanded = true
        TypeClipFeature.shared.diagnosticsExpanded = true
        render(
            MainWindowView(),
            width: 1000,
            height: 720,
            scheme: .light,
            to: url.appendingPathComponent(
                String(format: "%02d-window-typeclip-expanded-light.png", expandedNumber)
            )
        )
        TypeClipFeature.shared.advancedExpanded = false
        TypeClipFeature.shared.diagnosticsExpanded = false

        // 未授权状态：橙色提示卡 + 灰色敲入按钮
        let untrustedNumber = expandedNumber + 1
        AppState.shared.trusted = false
        AppState.shared.section = .feature(.typeClip)
        render(
            MainWindowView(),
            width: 1000,
            height: 720,
            scheme: .light,
            to: url.appendingPathComponent(
                String(format: "%02d-window-typeclip-untrusted-light.png", untrustedNumber)
            )
        )
        AppState.shared.trusted = true

        print("preview written to \(directory)")
        fflush(stdout)
    }

    private static func render<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat?,
        scheme: ColorScheme,
        to url: URL
    ) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        NSApp.appearance = appearance

        let root = view
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .key)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.translatesAutoresizingMaskIntoConstraints = true

        let initialHeight = height ?? 700
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: initialHeight)

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
        // 只做离屏渲染，不激活 App、不抢焦点。
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()

        let finalHeight: CGFloat
        if let height {
            finalHeight = height
        } else {
            let fit = hosting.fittingSize
            finalHeight = fit.height > 120 ? fit.height : initialHeight
        }

        hosting.frame = NSRect(x: 0, y: 0, width: width, height: finalHeight)
        window.setContentSize(NSSize(width: width, height: finalHeight))
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
        print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh) @ \(Int(finalHeight))pt")
        fflush(stdout)
    }
}
#endif

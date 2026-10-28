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
        KeyMappingFeature.shared.applyPreviewData()
        SmoothScrollFeature.shared.applyPreviewData()

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
                    width: 880,
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
            width: 880,
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
            width: 880,
            height: 720,
            scheme: .light,
            to: url.appendingPathComponent(
                String(format: "%02d-window-typeclip-untrusted-light.png", untrustedNumber)
            )
        )
        AppState.shared.trusted = true

        // 空状态：确认预设、说明和主按钮在 720pt 高度内排得下。
        let emptyNumber = untrustedNumber + 1
        AppState.shared.section = .feature(.keyMapping)
        KeyMappingFeature.shared.applyEmptyPreviewData()
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            render(
                MainWindowView(),
                width: 880,
                height: 720,
                scheme: scheme,
                to: url.appendingPathComponent(
                    String(format: "%02d-window-keymapping-empty-%@.png", emptyNumber, suffix)
                )
            )
        }
        KeyMappingFeature.shared.applyPreviewData()

        // 编辑弹窗单独渲染一张，方便检查鼠标键/快捷键/名称三段布局。
        if let sample = KeyMappingFeature.shared.mappings.first {
            let draft = KeyMappingDraft(
                id: sample.id,
                button: sample.button,
                combo: sample.combo,
                name: sample.name,
                enabled: sample.enabled,
                isNew: false
            )
            let model = KeyMappingEditorModel(
                draft: draft,
                feature: KeyMappingFeature.shared
            )
            let context = KeyMappingEditorContext(id: draft.id, model: model)
            let editorNumber = emptyNumber + 1
            render(
                KeyMappingEditor(context: context),
                width: 520,
                height: 700,
                scheme: .light,
                to: url.appendingPathComponent(
                    String(format: "%02d-window-keymapping-editor-light.png", editorNumber)
                )
            )

            // 新建状态：先清空映射，保证看到的是没有冲突的干净空表单。
            KeyMappingFeature.shared.applyEmptyPreviewData()
            let newDraft = KeyMappingDraft(
                id: UUID(),
                button: 3,
                combo: nil,
                name: "",
                enabled: true,
                isNew: true
            )
            let newModel = KeyMappingEditorModel(
                draft: newDraft,
                feature: KeyMappingFeature.shared
            )
            let newContext = KeyMappingEditorContext(id: newDraft.id, model: newModel)
            render(
                KeyMappingEditor(context: newContext),
                width: 520,
                height: 700,
                scheme: .light,
                to: url.appendingPathComponent(
                    String(format: "%02d-window-keymapping-editor-new-light.png", editorNumber + 1)
                )
            )
            KeyMappingFeature.shared.applyPreviewData()
        }

        // 翻译面板：词典、流式、错误与未配置。面板本身不读密钥文件、不发请求。
        let panelNumber = emptyNumber + 3
        let translation = TranslationFeature.shared

        let entry = DictionaryEntry(
            word: "hello",
            phonetic: "/həˈləʊ/",
            senses: [
                DictionarySense(
                    partOfSpeech: "int.",
                    translation: "你好；喂",
                    definition: "used as a greeting or to begin a phone conversation"
                ),
                DictionarySense(
                    partOfSpeech: "n.",
                    translation: "招呼；问候",
                    definition: "an utterance of “hello”; a greeting"
                ),
            ],
            examples: [
                DictionaryExample(
                    source: "Hello, it's nice to meet you.",
                    target: "你好，很高兴见到你。"
                ),
                DictionaryExample(
                    source: "She said hello to everyone in the room.",
                    target: "她向房间里的每个人打了招呼。"
                ),
            ],
            synonyms: ["hi", "greetings", "hey"]
        )

        translation.mode = .auto
        translation.input = "hello"
        translation.state = .dictionary(entry)
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            render(
                TranslationPanel(feature: translation, onClose: {}, onOpenSettings: {}),
                width: 600,
                height: 480,
                scheme: scheme,
                to: url.appendingPathComponent(
                    String(format: "%02d-panel-dictionary-%@.png", panelNumber, suffix)
                )
            )
        }

        translation.input = "This is a long sentence that should be translated as a paragraph."
        translation.state = .streaming(
            "这是一个用于检查流式翻译面板排版的示例译文。\n\n面板会保留换行，并在底部显示当前方向。"
        )
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            render(
                TranslationPanel(feature: translation, onClose: {}, onOpenSettings: {}),
                width: 600,
                height: 480,
                scheme: scheme,
                to: url.appendingPathComponent(
                    String(format: "%02d-panel-streaming-%@.png", panelNumber + 1, suffix)
                )
            )
        }

        translation.input = "hello"
        translation.state = .failed("API Key 无效或没有权限（401），请检查密钥。")
        render(
            TranslationPanel(feature: translation, onClose: {}, onOpenSettings: {}),
            width: 600,
            height: 480,
            scheme: .light,
            to: url.appendingPathComponent(
                String(format: "%02d-panel-failed-light.png", panelNumber + 2)
            )
        )

        translation.input = ""
        translation.state = .idle
        render(
            TranslationPanel(feature: translation, onClose: {}, onOpenSettings: {}),
            width: 600,
            height: 480,
            scheme: .dark,
            to: url.appendingPathComponent(
                String(format: "%02d-panel-not-configured-dark.png", panelNumber + 3)
            )
        )
        translation.mode = .auto

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
        hosting.autoresizingMask = [.width, .height]

        // 离屏截图不会带上窗口背景，侧栏和透明区域会变成黑色。
        // 垫一层窗口色再整体捕获，截图才和真实窗口一致。
        let container = NSView(frame: hosting.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.addSubview(hosting)

        let window = PreviewWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = container
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

        window.setContentSize(NSSize(width: width, height: finalHeight))
        container.frame = NSRect(x: 0, y: 0, width: width, height: finalHeight)
        hosting.frame = container.bounds
        hosting.layoutSubtreeIfNeeded()
        container.layoutSubtreeIfNeeded()
        container.displayIfNeeded()

        defer { window.orderOut(nil) }

        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
            print("preview failed (no rep): \(url.path)")
            return
        }
        container.cacheDisplay(in: container.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh) @ \(Int(finalHeight))pt")
        fflush(stdout)
    }
}
#endif

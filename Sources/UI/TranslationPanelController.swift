import AppKit
import Carbon
import SwiftUI

// MARK: - 面板窗口

/// NSPanel 的 Esc 和常用编辑快捷键在窗口层兜底。
/// 面板是非激活式的，不会把 App 的主窗口一起带到前台；因此
/// ⌘V/⌘C/⌘X/⌘A/⌘Z 不能依赖 App 菜单，必须在这里直接分发给文本视图。
final class TranslationPanelWindow: NSPanel {

    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if let textView = firstResponder as? NSTextView {
            if flags == .command {
                switch key {
                case "v":
                    textView.paste(nil)
                    return true
                case "c":
                    textView.copy(nil)
                    return true
                case "x":
                    textView.cut(nil)
                    return true
                case "a":
                    textView.selectAll(nil)
                    return true
                case "z":
                    textView.undoManager?.undo()
                    return true
                default:
                    break
                }
            } else if flags == [.command, .shift], key == "z" {
                textView.undoManager?.redo()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - 面板控制器

@MainActor
final class TranslationPanelController: NSObject {

    static let shared = TranslationPanelController()

    private var panel: TranslationPanelWindow?

    private var feature: TranslationFeature { .shared }

    private override init() {
        super.init()

        feature.presentPanel = { [weak self] in self?.toggle() }
        feature.dismissPanel = { [weak self] in self?.closePanel() }
        feature.openSettingsHandler = { [weak self] in self?.openSettings() }
    }

    /// 启动时实例化一次，把面板闭包挂到 feature 上。
    static func install() {
        _ = shared
    }

    // MARK: 显示/关闭

    func toggle() {
        let panel = ensurePanel()

        if panel.isVisible {
            if panel.isKeyWindow {
                closePanel()
            } else {
                panel.makeKeyAndOrderFront(nil)
                focusInput()
            }
            return
        }

        // 非激活面板：不调用 NSApp.activate，主窗口和原来的前台 App 都不会被顶上来。
        panel.makeKeyAndOrderFront(nil)
        focusInput()
    }

    func closePanel() {
        panel?.orderOut(nil)
    }

    // MARK: 设置

    private func openSettings() {
        closePanel()
        AppState.shared.open(.feature(.translate))
        MainWindowController.shared.show()
    }

    // MARK: 键盘焦点

    private func focusInput() {
        guard let panel, let content = panel.contentView else { return }
        if let textView = findEditableTextView(in: content) {
            panel.makeFirstResponder(textView)
            selectAllIfNeeded(textView)
        } else {
            // SwiftUI 的托管视图可能还没完成首次布局，下一个 runloop 再试。
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel, let content = panel.contentView else { return }
                if let textView = self.findEditableTextView(in: content) {
                    panel.makeFirstResponder(textView)
                    self.selectAllIfNeeded(textView)
                }
            }
        }
    }

    /// 重新呼出面板时选中上次输入，用户可以直接粘贴覆盖或按删除键清空。
    private func selectAllIfNeeded(_ textView: NSTextView) {
        guard !textView.string.isEmpty else { return }
        textView.selectAll(nil)
    }

    private func findEditableTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews {
            if let found = findEditableTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: 构造面板

    private func ensurePanel() -> TranslationPanelWindow {
        if let panel { return panel }

        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let height = min(760, max(560, visibleHeight * 0.72))
        let size = NSSize(width: 720, height: height)

        let panel = TranslationPanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "热键翻译"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 600, height: 480)
        panel.setContentSize(size)
        panel.onCancel = { [weak self] in self?.closePanel() }

        let hosting = NSHostingView(
            rootView: TranslationPanel(
                feature: feature,
                onClose: { [weak self] in self?.closePanel() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
        panel.contentView = hosting
        panel.center()
        // 换一个 autosave 名，避免恢复之前 600×480 的旧窗口尺寸。
        panel.setFrameAutosaveName("TranslationPanel.v2")

        self.panel = panel
        return panel
    }
}

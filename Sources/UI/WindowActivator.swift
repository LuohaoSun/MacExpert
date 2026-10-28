import AppKit
import SwiftUI

/// 激活策略的唯一入口：窗口出现前把 app 切到 .regular，
/// 需要抢焦点时再 activate。全工程的 `setActivationPolicy` 都收在这个文件里。
enum WindowActivation {
    @MainActor
    static func prepare(activate: Bool) {
        NSApp.setActivationPolicy(.regular)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// LSUIElement app 即使装了 NSApp.mainMenu，只要保持 .accessory，窗口成为 key 后
/// macOS 左上角菜单栏仍可能归上一个应用。这里只在 app 窗口可见时切到 .regular，
/// 全部窗口关闭后恢复 .accessory，避免长期占 Dock。
@MainActor
private final class WindowActivationController: NSObject {
    static let shared = WindowActivationController()

    private struct WeakWindow {
        weak var value: NSWindow?
    }

    private var registered: [ObjectIdentifier: WeakWindow] = [:]

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                           name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: nil)
    }

    func register(_ window: NSWindow?) {
        prune()
        guard let window else { return }
        registered[ObjectIdentifier(window)] = WeakWindow(value: window)
        if window.isKeyWindow { activate(window) }
    }

    private func isRegistered(_ window: NSWindow) -> Bool {
        registered[ObjectIdentifier(window)]?.value === window
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isRegistered(window) else { return }
        activate(window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isRegistered(window) else { return }
        registered.removeValue(forKey: ObjectIdentifier(window))
        DispatchQueue.main.async { [weak self] in self?.restoreAccessoryIfNeeded() }
    }

    private func activate(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func restoreAccessoryIfNeeded() {
        prune()
        if registered.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    private func prune() {
        registered = registered.filter { $0.value.value != nil }
    }
}

private final class WindowActivationProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            WindowActivationController.shared.register(self?.window)
        }
    }
}

/// 挂到每个 SwiftUI Window 的根视图；窗口出现时激活并置于最前，同时让菜单栏归属本 app。
struct WindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowActivationProbe(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

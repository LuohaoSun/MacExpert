import AppKit
import SwiftUI

/// 主窗口入口。窗口本体是 SwiftUI Window scene（窗口 chrome 全交给系统），
/// 这里只负责拿到 `openWindow` 动作并把窗口叫出来。
@MainActor
final class MainWindowController {

    static let shared = MainWindowController()

    private var openWindowAction: OpenWindowAction?
    private var pendingScenePresentation = false
    private var pendingActivate = true

    func register(_ action: OpenWindowAction) {
        openWindowAction = action
        guard pendingScenePresentation else { return }
        pendingScenePresentation = false
        let activate = pendingActivate
        DispatchQueue.main.async { [weak self] in
            self?.show(activate: activate)
        }
    }

    func show() {
        show(activate: true)
    }

    func show(activate: Bool) {
        guard let openWindowAction else {
            pendingScenePresentation = true
            pendingActivate = activate
            return
        }
        if !RuntimeFlags.suppressWindowActivation {
            WindowActivation.prepare(activate: activate)
        }
        DispatchQueue.main.async {
            openWindowAction(id: "main")
        }
    }
}

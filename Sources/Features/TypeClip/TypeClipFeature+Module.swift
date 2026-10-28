import Carbon
import Foundation

// MARK: - 热键 id

/// 集中定义全应用的热键 id，避免各功能各写魔法数字。
enum HotkeyID {
    static let typeClip: UInt32 = 1
    static let typeClipEnter: UInt32 = 2
}

// MARK: - FeatureModule 接入

extension TypeClipFeature: FeatureModule {

    var feature: Feature { .typeClip }

    func install() {
        HotkeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(cmdKey | controlKey),
            id: HotkeyID.typeClip,
            name: "敲入剪贴板（⌃⌘V）"
        ) { [weak self] in
            self?.handleHotkey(enter: false)
        }

        HotkeyCenter.shared.register(
            keyCode: UInt32(kVK_Return),
            carbonModifiers: UInt32(cmdKey | controlKey),
            id: HotkeyID.typeClipEnter,
            name: "敲入并回车（⌃⌘↩）"
        ) { [weak self] in
            self?.handleHotkey(enter: true)
        }
    }

    func onOpened() {
        refreshPasteboard(force: true)
    }

    func onActivated() {
        refreshPasteboard()
    }

    func prepareForTermination() {
        engine.cancel()
    }
}

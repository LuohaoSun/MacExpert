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
        syncHotkeys()
    }

    /// 模块总开关同时控制全局热键的注册。
    /// 只让处理函数 return 不够：Carbon 仍会吞掉按键，别的应用也拿不到。
    func syncHotkeys() {
        if enabled {
            registerHotkeys()
        } else {
            unregisterHotkeys()
        }
    }

    private func registerHotkeys() {
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

    private func unregisterHotkeys() {
        HotkeyCenter.shared.unregister(id: HotkeyID.typeClip)
        HotkeyCenter.shared.unregister(id: HotkeyID.typeClipEnter)
    }

    func onOpened() {
        refreshPasteboard(force: true)
    }

    func onActivated() {
        refreshPasteboard()
    }

    func prepareForTermination() {
        engine.cancel()
        unregisterHotkeys()
    }
}

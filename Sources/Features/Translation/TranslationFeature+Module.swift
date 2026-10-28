import Carbon
import Foundation

// MARK: - 热键 id

extension HotkeyID {
    static let translation: UInt32 = 0x54524E53 // 'TRNS'
}

// MARK: - FeatureModule 接入

extension TranslationFeature: FeatureModule {

    var feature: Feature { .translate }

    var hotkeyFailure: HotkeyFailure? {
        HotkeyCenter.shared.failures.first { $0.id == HotkeyID.translation }
    }

    var statusLine: String? {
        guard enabled, let failure = hotkeyFailure else { return nil }
        return "热键翻译：⌥Space 被占用（\(failure.message)）"
    }

    func install() {
        syncHotkey()
    }

    func onOpened() {
        retryHotkeyIfNeeded()
    }

    func onActivated() {
        retryHotkeyIfNeeded()
    }

    func prepareForTermination() {
        HotkeyCenter.shared.unregister(id: HotkeyID.translation)
        cancel()
        dismissPanel?()
    }

    /// 总开关同时控制热键；只让处理函数 return 不够，Carbon 仍会吞掉 ⌥Space。
    func syncHotkey() {
        guard !RuntimeFlags.isRenderingPreview else { return }

        HotkeyCenter.shared.unregister(id: HotkeyID.translation)
        guard enabled else { return }

        HotkeyCenter.shared.register(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            id: HotkeyID.translation,
            name: "热键翻译（⌥Space）"
        ) { [weak self] in
            guard let self, self.enabled else { return }
            self.openPanel()
        }
    }

    /// 用户可能刚关掉占用 ⌥Space 的应用；回到前台时补注册一次。
    private func retryHotkeyIfNeeded() {
        guard enabled, hotkeyFailure != nil, !RuntimeFlags.isRenderingPreview else { return }
        syncHotkey()
    }
}

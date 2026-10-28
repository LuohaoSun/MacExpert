import AppKit
import Carbon

/// Carbon `RegisterEventHotKey` 全局热键（与 Hammerspoon 同一机制）。
/// 不需要辅助功能权限就能注册；真正模拟键盘时才会用到 TCC 授权。
/// 多个功能共用同一个处理器，按 id 分发。
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var installed = false
    private let signature = OSType(0x4D457870) // 'MExp'

    func register(keyCode: UInt32, carbonModifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        actions[id] = action
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if let action = HotkeyCenter.shared.actions[hotKeyID.id] {
                DispatchQueue.main.async(execute: action)
            }
            return noErr
        }, 1, &eventSpec, nil, nil)
    }
}

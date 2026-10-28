import AppKit
import Carbon
import Combine

/// 一次热键注册失败。设置页据此提示用户，但不影响功能是否可用。
struct HotkeyFailure: Identifiable, Hashable {
    /// 热键 id（与 `HotkeyID` 常量对应）。
    let id: UInt32
    /// 人话名字，用于提示，例如「敲入剪贴板（⌃⌘V）」。
    let name: String
    /// `RegisterEventHotKey` 返回的 OSStatus。
    let status: OSStatus
    /// 已翻译好的失败原因。
    let message: String
}

/// Carbon `RegisterEventHotKey` 全局热键（与 Hammerspoon 同一机制）。
/// 不需要辅助功能权限就能注册；真正模拟键盘时才会用到 TCC 授权。
/// 多个功能共用同一个处理器，按 id 分发。
final class HotkeyCenter: ObservableObject {

    static let shared = HotkeyCenter()

    /// 最近一次注册失败的热键。注册失败不会把功能标成不可用，只在这里留痕。
    @Published private(set) var failures: [HotkeyFailure] = []

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    private let signature = OSType(0x4D457870) // 'MExp'

    /// 注册热键。成功返回 true；失败时记录到 `failures` 并返回 false。
    @discardableResult
    func register(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        id: UInt32,
        name: String,
        action: @escaping () -> Void
    ) -> Bool {
        // 同一 id 重复注册时先释放旧 ref，避免系统里残留两份占用。
        unregister(id: id)

        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            let failure = HotkeyFailure(
                id: id,
                name: name,
                status: status,
                message: Self.describe(status)
            )
            failures.append(failure)
            // 不要用 AppLog.write：那会覆盖整个日志文件，热键失败只该留一行。
            NSLog("[MacExpert] 热键注册失败：%@", "\(name)（id=\(id)）OSStatus=\(status) \(failure.message)")
            return false
        }

        refs[id] = ref
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        actions.removeValue(forKey: id)
        failures.removeAll { $0.id == id }
    }

    private static func describe(_ status: OSStatus) -> String {
        switch status {
        case OSStatus(-9878): return "快捷键已被其他应用占用"
        case OSStatus(-9879): return "热键参数无效"
        case OSStatus(-50): return "参数错误"
        default: return "系统返回 OSStatus \(status)"
        }
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

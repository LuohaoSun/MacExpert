import Carbon
import CoreGraphics

/// CGEvent 发送原语: 把"修饰键 flagsChanged / 字符 keyDown-keyUp / 兜底松开修饰键"
/// 这几种事件形状收敛到一处, 供敲入引擎和将来的按键映射共用。
///
/// 事件形状是实测结论, 不要随手改:
/// - 修饰键必须是 .flagsChanged(真实键盘的修饰键从不产生 keyDown/keyUp), 远程客户端靠它跟踪修饰状态;
/// - 字符事件必须带 flags(含左右设备位)并写入 unicode 串, 否则读 unicode 的接收方拿不到字符;
/// - 不要加 .maskNonCoalesced, 带它的合成事件会被部分远程客户端当成两个事件处理;
/// - 统一 post 到 .cgSessionEventTap。
final class EventInjector {

    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .combinedSessionState)
    }

    /// 修饰键事件: 类型固定为 .flagsChanged, flags 表示当前所有修饰键的状态。
    func postModifier(keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }

    /// 字符事件: flags 带修饰位(含设备位), 并像真实事件一样写入该字符的 unicode 串
    /// (真实键盘事件由系统填好, 合成事件不填, 读 unicode 串的接收方会拿不到字符)。
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, unicode: Character?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        if let unicode {
            let units = Array(String(unicode).utf16)
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
            }
        }
        event.post(tap: .cgSessionEventTap)
    }

    /// 中断兜底: 修饰键按下后、抬起前被打断时, 抬起事件不会再发,
    /// 补发 shift/option 的 flagsChanged(flags 为空 = 全部松开)避免卡在按下状态
    /// (多余的抬起无副作用)。
    func releaseStickyModifiers() {
        for key in [CGKeyCode(kVK_Shift), CGKeyCode(kVK_Option)] {
            postModifier(keyCode: key, down: false, flags: [])
        }
    }

    /// 修饰键的修饰位 + 设备位(区分左右): NX_DEVICELSHIFTKEYMASK / NX_DEVICELALTKEYMASK。
    static func modifierBits(_ keyCode: CGKeyCode) -> CGEventFlags {
        if Int(keyCode) == Int(kVK_Shift) { return [.maskShift, CGEventFlags(rawValue: 0x0002)] }
        if Int(keyCode) == Int(kVK_Option) { return [.maskAlternate, CGEventFlags(rawValue: 0x0020)] }
        return []
    }

    /// 时间轴日志里的修饰键缩写。
    static func modTag(_ key: CGKeyCode) -> String {
        Int(key) == Int(kVK_Shift) ? "S" : "A"
    }
}

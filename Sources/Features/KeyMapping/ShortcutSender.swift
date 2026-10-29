import CoreGraphics
import Foundation

// MARK: - 快捷键发送

/// 把一条组合键拆成真实的修饰键 + 字符键事件。
/// 使用串行后台队列，事件 tap 回调只负责入队，不阻塞鼠标事件。
///
/// 发送间隔用于远程桌面/堡垒机：修饰键和字符键贴得太近时，
/// 远端转发层可能来不及登记修饰状态，`⇧3` 会退化成裸 `3`。
final class ShortcutSender {

    /// 私有事件源 + HID 投递: WindowServer 才会把方向键组合当成系统快捷键。
    /// session 层 + combinedSessionState 只能把 ⌃← 送进前台 App，切不了桌面。
    private let injector = EventInjector(stateID: .privateState, tap: .cghidEventTap)
    private let queue = DispatchQueue(
        label: "com.slh.macexpert.keymapping.send",
        qos: .userInteractive
    )
    private let lock = NSLock()
    private var pressed: [Modifier] = []

    func send(_ combo: KeyCombo, delayMs: Double) {
        let delay = TimeInterval(min(max(delayMs, 0), 200)) / 1000
        // 触发它的鼠标 up 事件要先在系统里处理完再送键盘事件；
        // 两者抢顺序时，⌃← 这类系统快捷键会被丢掉。
        let leadIn: TimeInterval = 0.03
        queue.async { [weak self] in
            guard let self else { return }
            self.pause(leadIn)
            self.post(combo, delay: delay)
        }
    }

    /// 退出/中断时兜底释放修饰键，避免系统里留下按下的 ⌘/⇧。
    func releaseAll() {
        queue.sync {
            lock.lock()
            let modifiers = pressed
            pressed.removeAll()
            lock.unlock()

            for modifier in modifiers.reversed() {
                injector.postModifier(keyCode: modifier.keyCode, down: false, flags: [])
            }
        }
    }

    private func post(_ combo: KeyCombo, delay: TimeInterval) {
        var flags: CGEventFlags = []

        for modifier in combo.orderedModifiers {
            flags.formUnion(modifier.eventFlags)
            injector.postModifier(keyCode: modifier.keyCode, down: true, flags: flags)
            addPressed(modifier)
            pause(delay)
        }

        // 方向键 / F 键在真实事件里带 Function 位，系统的 symbolic hotkey
        // 按这个位匹配；缺了它 ⌃← / ⌃→ 只会被当成普通方向键。
        let keyFlags = combo.keyEventFlags(base: flags)
        injector.postKey(keyCode: combo.keyCode, flags: keyFlags, down: true, unicode: nil)
        pause(delay)
        injector.postKey(keyCode: combo.keyCode, flags: keyFlags, down: false, unicode: nil)
        pause(delay)

        for modifier in combo.orderedModifiers.reversed() {
            flags.remove(modifier.eventFlags)
            injector.postModifier(keyCode: modifier.keyCode, down: false, flags: flags)
            removePressed(modifier)
            pause(delay)
        }
    }

    private func pause(_ delay: TimeInterval) {
        guard delay > 0 else { return }
        Thread.sleep(forTimeInterval: delay)
    }

    private func addPressed(_ modifier: Modifier) {
        lock.lock()
        defer { lock.unlock() }
        if !pressed.contains(modifier) {
            pressed.append(modifier)
        }
    }

    private func removePressed(_ modifier: Modifier) {
        lock.lock()
        defer { lock.unlock() }
        pressed.removeAll { $0 == modifier }
    }
}

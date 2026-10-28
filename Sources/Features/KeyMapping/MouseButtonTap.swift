import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - 按钮吞噬状态

/// 鼠标键按下并命中映射后，要把它后续的 up/drag 一并吞掉，
/// 否则目标应用可能收到不成对的抬起事件或开始拖拽。
struct ButtonPressTracker {
    private var consumed: Set<Int> = []

    mutating func down(_ button: Int, consume: Bool) -> Bool {
        if consume {
            consumed.insert(button)
        } else {
            consumed.remove(button)
        }
        return consume
    }

    mutating func up(_ button: Int) -> Bool {
        consumed.remove(button) != nil
    }

    mutating func dragged(_ button: Int) -> Bool {
        consumed.contains(button)
    }

    mutating func reset() {
        consumed.removeAll()
    }
}

// MARK: - 鼠标监听

/// 全局鼠标按键监听。只关心 `otherMouse*` 里的按钮 2...31：
/// 2 是中键，3/4 通常是两个侧键。
///
/// 使用 `.defaultTap` 才能吞掉原事件；这需要辅助功能权限（与剪贴板敲入共用）。
/// 事件源挂在主 RunLoop 的 `.commonModes`，菜单打开、窗口拖拽时仍然工作。
final class MouseButtonTap {

    enum State: Equatable {
        case stopped
        case running
        case permissionDenied
        case failed(String)
    }

    private(set) var state: State = .stopped

    /// 返回 true 表示这个按钮已被映射，监听器会吞掉 down/up/drag。
    var onButtonDown: ((Int) -> Bool)?
    var onButtonUp: ((Int) -> Void)?
    /// 每次收到 2...31 的鼠标键都回调，用于诊断面板显示编号。
    var onEvent: ((Int) -> Void)?
    /// 编辑弹窗录制鼠标键时优先把下一次按键交给它，并吞掉原事件。
    var captureHandler: ((Int) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tracker = ButtonPressTracker()
    private var disabledCount = 0

    @discardableResult
    func start() -> Bool {
        if state == .running, tap != nil { return true }
        if tap != nil { stop() }

        guard AXIsProcessTrusted() else {
            state = .permissionDenied
            return false
        }

        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            state = .failed("无法创建鼠标监听（系统拒绝）")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            state = .failed("无法创建鼠标监听事件源")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        self.tracker.reset()
        self.disabledCount = 0
        self.state = .running
        return true
    }

    func stop() {
        captureHandler = nil
        tracker.reset()

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        source = nil
        tap = nil
        state = .stopped
    }

    deinit {
        stop()
    }

    // MARK: - 回调

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MouseButtonTap>.fromOpaque(refcon).takeUnretainedValue()
        return tap.handle(type, event: event)
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            disabledCount += 1
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            NSLog("[MacExpert] 鼠标监听被系统暂停，已尝试恢复（第 %d 次）", disabledCount)
            return Unmanaged.passUnretained(event)
        }

        guard type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged else {
            return Unmanaged.passUnretained(event)
        }

        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        guard number >= 2, number <= 31 else {
            return Unmanaged.passUnretained(event)
        }
        let button = Int(number)
        onEvent?(button)

        switch type {
        case .otherMouseDown:
            if let capture = captureHandler {
                captureHandler = nil
                _ = tracker.down(button, consume: true)
                capture(button)
                return nil
            }

            let consume = onButtonDown?(button) ?? false
            _ = tracker.down(button, consume: consume)
            return consume ? nil : Unmanaged.passUnretained(event)

        case .otherMouseUp:
            let consumed = tracker.up(button)
            onButtonUp?(button)
            return consumed ? nil : Unmanaged.passUnretained(event)

        case .otherMouseDragged:
            return tracker.dragged(button) ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

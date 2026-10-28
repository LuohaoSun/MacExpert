import AppKit
import CoreGraphics

// MARK: - 滚轮事件监听

/// 全局滚轮监听。只关心 `.scrollWheel`：
/// 分类、原地反向或者把增量交给引擎都在这里决定，tap 本身不做任何等待。
///
/// 用 `.defaultTap` 才能吞掉原事件，需要辅助功能权限（与其他模块共用）。
/// 事件源挂在主 RunLoop 的 `.commonModes`，菜单打开、窗口拖拽时仍然工作。
final class ScrollTap {

    enum State: Equatable {
        case stopped
        case running
        case permissionDenied
        case failed(String)
    }

    enum Action {
        case passThrough
        case swallow
    }

    private(set) var state: State = .stopped {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    /// 返回 `.swallow` 时原事件被丢弃；回调里只做分类和入队，不能阻塞等待引擎。
    var handler: ((ScrollSample, CGEvent) -> Action)?
    var onStateChange: ((State) -> Void)?
    /// 系统唤醒后回调，让上层重置引擎；tap 自己随后会重启。
    var onWake: (() -> Void)?

    private(set) var disabledCount = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?

    deinit {
        removeWakeObserver()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    @discardableResult
    func start() -> Bool {
        if state == .running, tap != nil { return true }
        if tap != nil { stop() }

        guard AXIsProcessTrusted() else {
            state = .permissionDenied
            return false
        }

        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            state = .failed("无法创建滚轮监听（系统拒绝）")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            state = .failed("无法创建滚轮监听事件源")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        self.disabledCount = 0
        self.state = .running
        registerWakeObserver()
        return true
    }

    func stop() {
        removeWakeObserver()

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

    /// 睡眠唤醒后系统常常把 tap 挂起，直接重建一次最稳。
    func restart() {
        guard state == .running else { return }
        stop()
        _ = start()
    }

    // MARK: - 唤醒

    private func registerWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onWake?()
            self.restart()
        }
    }

    private func removeWakeObserver() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    // MARK: - 回调

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<ScrollTap>.fromOpaque(refcon).takeUnretainedValue()
        return tap.handle(type, event: event)
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            disabledCount += 1
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            NSLog("[MacExpert] 滚轮监听被系统暂停，已尝试恢复（第 %d 次）", disabledCount)
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel, let handler else {
            return Unmanaged.passUnretained(event)
        }

        switch handler(ScrollSample(event: event), event) {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        }
    }
}

// MARK: - CGEvent 桥接

extension ScrollSample {
    init(event: CGEvent) {
        self.init(
            dxPoints: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
            dyPoints: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
            fixedDX: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            fixedDY: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            lineDeltaX: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
            lineDeltaY: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
            momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
            flags: event.flags,
            targetPID: pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
    }
}

extension CGEvent {
    /// 平滑关闭时的原地反向：只动指定轴，并且用反向前的样本值写回三个增量。
    /// 未反向的轴一个字节都不碰。
    ///
    /// 写入顺序必须是「行 → 固定点 → 点」：系统在写行增量时会按每行 8pt
    /// 重算点增量，最后写点增量才能保留原来的像素距离。
    func reverseScrollFields(_ sample: ScrollSample, vertical: Bool, horizontal: Bool) {
        if vertical {
            setIntegerValueField(
                .scrollWheelEventDeltaAxis1,
                value: -Int64(sample.lineDeltaY)
            )
            setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis1,
                value: -sample.fixedDY
            )
            setIntegerValueField(
                .scrollWheelEventPointDeltaAxis1,
                value: -Int64(sample.dyPoints.rounded())
            )
        }
        if horizontal {
            setIntegerValueField(
                .scrollWheelEventDeltaAxis2,
                value: -Int64(sample.lineDeltaX)
            )
            setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: -sample.fixedDX
            )
            setIntegerValueField(
                .scrollWheelEventPointDeltaAxis2,
                value: -Int64(sample.dxPoints.rounded())
            )
        }
    }
}

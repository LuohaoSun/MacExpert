import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - 平滑滚动功能

final class SmoothScrollFeature: ObservableObject {

    static let shared = SmoothScrollFeature()

    struct LastInput: Equatable {
        let dxPoints: Double
        let dyPoints: Double
        let lineDeltaX: Int
        let lineDeltaY: Int
        let captured: Bool
        let reversed: Bool
        let passthrough: ScrollPassthrough?
        let pid: pid_t
        let boost: Double
        let date: Date
    }

    private let store: SmoothScrollStore
    private let tap = ScrollTap()
    private let poster = ScrollPoster()
    private let engineQueue = DispatchQueue(
        label: "com.slh.macexpert.smoothscroll",
        qos: .userInteractive
    )
    private var engine = SmoothScrollEngine()
    private var ticker: DispatchSourceTimer?
    private var lastTickUptime: UInt64 = 0
    private var activeFlags: CGEventFlags = []
    private var accelerometer = ScrollAcceleration()
    private var lastRecordTime: TimeInterval = 0
    private var isPreview = false
    private var installed = false

    @Published var enabled: Bool {
        didSet {
            guard !isPreview else { return }
            store.setEnabled(enabled)
            updateTap()
            if !enabled { resetEngine() }
        }
    }

    @Published var smooth: Bool {
        didSet {
            guard !isPreview else { return }
            store.setSmooth(smooth)
            // 平滑中途关掉时，停止继续发送合成事件；后续滚轮改走原地反向。
            if !smooth { resetEngine() }
        }
    }

    @Published var reverseVertical: Bool {
        didSet {
            guard !isPreview else { return }
            store.setReverseVertical(reverseVertical)
        }
    }

    @Published var reverseHorizontal: Bool {
        didSet {
            guard !isPreview else { return }
            store.setReverseHorizontal(reverseHorizontal)
        }
    }

    @Published var durationMs: Double {
        didSet {
            let clamped = SmoothScrollStore.clampDuration(durationMs)
            if clamped != durationMs {
                durationMs = clamped
                return
            }
            guard !isPreview else { return }
            store.setDurationMs(clamped)
        }
    }

    @Published var gain: Double {
        didSet {
            let clamped = SmoothScrollStore.clampGain(gain)
            if clamped != gain {
                gain = clamped
                return
            }
            guard !isPreview else { return }
            store.setGain(clamped)
        }
    }

    @Published var accelerationEnabled: Bool {
        didSet {
            guard !isPreview else { return }
            store.setAccelerationEnabled(accelerationEnabled)
            if !accelerationEnabled { accelerometer.reset() }
        }
    }

    @Published var accelerationMax: Double {
        didSet {
            let clamped = SmoothScrollStore.clampAccelerationMax(accelerationMax)
            if clamped != accelerationMax {
                accelerationMax = clamped
                return
            }
            guard !isPreview else { return }
            store.setAccelerationMax(clamped)
        }
    }

    @Published private(set) var tapState: ScrollTap.State = .stopped
    @Published private(set) var lastInput: LastInput?

    // 页面临时状态，不落盘。
    @Published var advancedExpanded = false

    private init(store: SmoothScrollStore = SmoothScrollStore()) {
        self.store = store
        self.enabled = store.isEnabled
        self.smooth = store.isSmooth
        self.reverseVertical = store.reverseVertical
        self.reverseHorizontal = store.reverseHorizontal
        self.durationMs = store.durationMs
        self.gain = store.gain
        self.accelerationEnabled = store.accelerationEnabled
        self.accelerationMax = store.accelerationMax
    }

    // MARK: - 生命周期

    func start() {
        guard !installed else { return }
        installed = true
        // 加速已经并入滚动效果，不再提供关闭开关；旧版本遗留的 false 直接迁移为开启。
        accelerationEnabled = true

        tap.handler = { [weak self] sample, event in
            guard let self else { return .passThrough }
            return self.handle(sample: sample, event: event)
        }
        tap.onStateChange = { [weak self] state in
            self?.tapState = state
        }
        tap.onWake = { [weak self] in
            self?.resetEngine()
        }

        updateTap()
    }

    func shutdown() {
        tap.handler = nil
        tap.stop()
        tapState = .stopped
        accelerometer.reset()
        stopEngine()
    }

    /// App 激活、页面打开或授权状态变化时调用。
    func refreshPermission() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        guard AXIsProcessTrusted() else {
            if tap.state != .stopped { tap.stop() }
            tapState = .permissionDenied
            resetEngine()
            return
        }
        updateTap()
    }

    func restartTap() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        tap.stop()
        updateTap()
    }

    // MARK: - 设置

    func resetToDefaults() {
        smooth = true
        reverseVertical = false
        reverseHorizontal = false
        durationMs = SmoothScrollStore.defaultDurationMs
        gain = SmoothScrollStore.defaultGain
        accelerationEnabled = true
        accelerationMax = SmoothScrollStore.defaultAccelerationMax
    }

    // MARK: - 滚轮处理

    private func handle(sample: ScrollSample, event: CGEvent) -> ScrollTap.Action {
        guard enabled else { return .passThrough }

        switch sample.plan(
            smooth: smooth,
            reverseVertical: reverseVertical,
            reverseHorizontal: reverseHorizontal
        ) {
        case .passThrough(let reason):
            record(sample, captured: false, reversed: false, passthrough: reason, boost: 1)
            return .passThrough

        case .modifyAndPass(let vertical, let horizontal):
            if vertical || horizontal {
                event.reverseScrollFields(
                    sample,
                    vertical: vertical,
                    horizontal: horizontal
                )
            }
            record(
                sample,
                captured: true,
                reversed: vertical || horizontal,
                passthrough: nil,
                boost: 1
            )
            return .passThrough

        case .swallowAndSmooth(let dx, let dy):
            let boost: Double
            if accelerationEnabled {
                accelerometer.maxBoost = accelerationMax
                boost = accelerometer.boost(
                    dx: dx,
                    dy: dy,
                    at: ProcessInfo.processInfo.systemUptime
                )
            } else {
                boost = 1
            }
            record(
                sample,
                captured: true,
                reversed: reverseVertical || reverseHorizontal,
                passthrough: nil,
                boost: boost
            )
            // tap 回调只入队，不等引擎队列，保证滚轮事件立刻返回。
            enqueue(dx: dx * boost, dy: dy * boost, flags: sample.flags)
            return .swallow
        }
    }

    private func record(
        _ sample: ScrollSample,
        captured: Bool,
        reversed: Bool,
        passthrough: ScrollPassthrough?,
        boost: Double
    ) {
        // 触控板每秒能产生上百条事件，界面只需要看到最近一次；
        // 节流到 4Hz，避免主线程被无谓的 SwiftUI 重绘拖住。
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastRecordTime < 0.25 { return }
        lastRecordTime = now

        lastInput = LastInput(
            dxPoints: sample.dxPoints,
            dyPoints: sample.dyPoints,
            lineDeltaX: sample.lineDeltaX,
            lineDeltaY: sample.lineDeltaY,
            captured: captured,
            reversed: reversed,
            passthrough: passthrough,
            pid: sample.targetPID,
            boost: boost,
            date: Date()
        )
    }

    // MARK: - 引擎与计时器

    private func enqueue(dx: Double, dy: Double, flags: CGEventFlags) {
        let duration = durationMs
        let gain = gain

        engineQueue.async { [weak self] in
            guard let self else { return }
            self.engine.durationMs = duration
            self.engine.gain = gain
            self.activeFlags = flags

            if self.ticker == nil {
                self.lastTickUptime = DispatchTime.now().uptimeNanoseconds
                self.startTicker()
            }
            self.engine.enqueue(dx: dx, dy: dy)
        }
    }

    private func startTicker() {
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(8),
            repeating: .milliseconds(8),
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        ticker = timer
        timer.resume()
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTickUptime == 0
            ? 0.008
            : Double(now - lastTickUptime) / 1_000_000_000
        lastTickUptime = now

        let dt = min(max(elapsed, 0.001), 0.05)
        guard let output = engine.tick(dt: dt) else {
            stopTicker()
            return
        }

        poster.post(
            dx: output.dx,
            dy: output.dy,
            phase: output.phase,
            flags: activeFlags
        )

        if output.finished { stopTicker() }
    }

    private func stopEngine() {
        engineQueue.sync {
            stopTicker()
            engine.reset()
        }
    }

    private func resetEngine() {
        accelerometer.reset()
        engineQueue.async { [weak self] in
            guard let self else { return }
            self.stopTicker()
            self.engine.reset()
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
        lastTickUptime = 0
    }

    // MARK: - tap 开关

    private func updateTap() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        if enabled {
            if tap.state != .running {
                _ = tap.start()
            }
        } else if tap.state != .stopped {
            tap.stop()
        }
        tapState = tap.state
    }
}

// MARK: - 预览数据

#if MACEXPERT_DEV_HOOKS
extension SmoothScrollFeature {
    func applyPreviewData() {
        isPreview = true
        enabled = true
        smooth = true
        accelerationEnabled = true
        reverseVertical = true
        tapState = .running
        lastInput = LastInput(
            dxPoints: 0,
            dyPoints: 30,
            lineDeltaX: 0,
            lineDeltaY: 3,
            captured: true,
            reversed: true,
            passthrough: nil,
            pid: 1234,
            boost: 2.1,
            date: Date()
        )
    }
}
#endif

import Foundation

// MARK: - 平滑滚动引擎

/// 纯插值逻辑，不持有计时器，也不读真实时间：每次 `tick(dt:)` 由调用方给 dt，
/// 测试里可以按固定步长推进，不受机器负载影响。
///
/// 每个轴维护：
/// - `target`：输入累加后的目标位置；
/// - `current`：当前连续位置；
/// - `published`：已经发出去的累计整数；
/// - `remainder`：尚未凑成整数的余数（用来核对没有丢小数）。
///
/// 输出永远是「累计整数差」，所以小数部分会一直留在 `current` 里，
/// 不会因为逐帧取整而丢掉。
struct SmoothScrollEngine {

    struct Axis: Equatable {
        var target: Double = 0
        var current: Double = 0
        var published: Int = 0
        var remainder: Double = 0

        var isSettled: Bool { current == target }
    }

    struct Output: Equatable {
        var dx: Int
        var dy: Int
        var phase: ScrollPhase
        var finished: Bool
    }

    var durationMs: Double = 300
    var gain: Double = 1

    private(set) var x = Axis()
    private(set) var y = Axis()
    private(set) var isActive = false
    private var started = false

    var isIdle: Bool { !isActive }

    mutating func reset() {
        x = Axis()
        y = Axis()
        isActive = false
        started = false
    }

    /// 新输入只累加目标，不清零 current/target。
    /// 反向或中途换向时直接改目标值，画面会顺着当前速度拐弯，不会卡一下。
    mutating func enqueue(dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        if !isActive {
            isActive = true
            started = false
        }
        x.target += dx * gain
        y.target += dy * gain
    }

    /// 推进一帧。返回 nil 表示引擎已经空闲。
    /// tau = duration / 3，指数曲线在大约一个 duration 内走完 95%。
    mutating func tick(dt: Double) -> Output? {
        guard isActive else { return nil }

        let tau = max(durationMs, 1) / 1000 / 3
        let factor = 1 - exp(-max(dt, 0.001) / tau)

        let dx = x.advance(factor: factor)
        let dy = y.advance(factor: factor)

        let phase: ScrollPhase = started ? .changed : .began
        started = true

        if x.isSettled, y.isSettled, dx == 0, dy == 0 {
            isActive = false
            started = false
            return Output(dx: 0, dy: 0, phase: .ended, finished: true)
        }

        return Output(dx: dx, dy: dy, phase: phase, finished: false)
    }
}

private extension SmoothScrollEngine.Axis {

    /// 返回这一帧应该发出的整数增量。
    mutating func advance(factor: Double) -> Int {
        let delta = target - current

        if abs(delta) < 0.5 {
            // 亚像素的尾差直接吸附，避免永远差一点点。
            current = target
        } else {
            current += delta * factor

            // 指数曲线在尾部会越来越慢；离目标还有 1pt 以上时每帧至少走 1pt，
            // 否则最后几 pt 会拖出很长的尾巴。current 不会越过 target。
            if abs(target - current) >= 1 {
                let direction: Double = target > current ? 1 : -1
                let stepped = current + direction
                current = direction > 0 ? min(stepped, target) : max(stepped, target)
            }
        }

        // 浮点累加会把 10 × 0.4 算成 3.9999999999999996；
        // 加一个极小量再取整，避免因为末位误差整整吞掉 1pt。
        let snapped = current + (current >= 0 ? 1e-9 : -1e-9)
        let whole = Int(snapped.rounded(.towardZero))
        let out = whole - published
        published = whole
        remainder = current - Double(whole)
        return out
    }
}

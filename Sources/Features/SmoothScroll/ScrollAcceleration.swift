import Foundation

// MARK: - 快速滚动加速

/// 根据滚轮的物理速度（点/秒）给单格距离加成。
///
/// 用速度而不是事件频率，是为了让经典滚轮和高分辨率滚轮共用同一套阈值：
/// 前者一格 33.6pt、每秒十几格；后者单次增量小、但每秒事件多。
/// 慢速时保持 1×，连续快速滚动时平滑升到 `maxBoost`。
struct ScrollAcceleration {

    /// 低于这个速度不加速。
    static let slowSpeed: Double = 250
    /// 达到这个速度时用满最大倍率。
    static let fastSpeed: Double = 1200
    /// 超过这个间隔视为新的一轮滚动，速度和方向都重新算。
    static let burstTimeout: Double = 0.35

    var maxBoost: Double = 2.5

    private(set) var smoothedSpeed: Double = 0
    private var lastTime: Double?
    private var lastDirection: Int = 0

    mutating func reset() {
        smoothedSpeed = 0
        lastTime = nil
        lastDirection = 0
    }

    /// `time` 用单调时钟（秒）。返回 1...maxBoost 的倍率。
    mutating func boost(dx: Double, dy: Double, at time: Double) -> Double {
        let direction: Int
        if dy != 0 {
            direction = dy > 0 ? 1 : -1
        } else if dx != 0 {
            direction = dx > 0 ? 1 : -1
        } else {
            return 1
        }

        let magnitude = max(abs(dx), abs(dy))
        let isNewBurst: Bool
        let interval: Double

        if let lastTime {
            interval = max(time - lastTime, 0.001)
            isNewBurst = interval > Self.burstTimeout || direction != lastDirection
        } else {
            interval = 0
            isNewBurst = true
        }

        self.lastTime = time
        lastDirection = direction

        if isNewBurst {
            // 停手、换向后的第一格不加速，给用户一个可预期的起点。
            smoothedSpeed = 0
            return 1
        }

        let instantSpeed = magnitude / interval
        // 用 EMA 过滤单次抖动；0.35 的权重让连续滚动大约三四格后达到满加速。
        smoothedSpeed = smoothedSpeed * 0.65 + instantSpeed * 0.35

        let span = Self.fastSpeed - Self.slowSpeed
        let t = min(max((smoothedSpeed - Self.slowSpeed) / span, 0), 1)
        let cap = max(maxBoost, 1)
        return 1 + (cap - 1) * pow(t, 1.4)
    }
}

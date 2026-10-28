import Foundation

// MARK: - 平滑滚动设置

/// 和 `KeyMappingStore` 一样：一个薄薄的 UserDefaults 包装，
/// 所有读取都在这里夹到允许范围，避免界面上出现越界值。
struct SmoothScrollStore {

    static let enabledKey = "smoothScroll.enabled"
    static let smoothKey = "smoothScroll.smooth"
    static let reverseVerticalKey = "smoothScroll.reverseVertical"
    static let reverseHorizontalKey = "smoothScroll.reverseHorizontal"
    static let durationKey = "smoothScroll.durationMs"
    static let gainKey = "smoothScroll.gain"
    static let accelerationEnabledKey = "smoothScroll.accelerationEnabled"
    static let accelerationMaxKey = "smoothScroll.accelerationMax"

    static let defaultDurationMs: Double = 180
    static let durationRange: ClosedRange<Double> = 80...400
    static let defaultGain: Double = 1.0
    static let gainRange: ClosedRange<Double> = 0.5...4.0
    static let defaultAccelerationMax: Double = 2.5
    static let accelerationMaxRange: ClosedRange<Double> = 1.5...10.0

    static func clampDuration(_ value: Double) -> Double {
        min(max(value, durationRange.lowerBound), durationRange.upperBound)
    }

    static func clampGain(_ value: Double) -> Double {
        min(max(value, gainRange.lowerBound), gainRange.upperBound)
    }

    static func clampAccelerationMax(_ value: Double) -> Double {
        min(max(value, accelerationMaxRange.lowerBound), accelerationMaxRange.upperBound)
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
    }

    var isSmooth: Bool {
        defaults.object(forKey: Self.smoothKey) as? Bool ?? true
    }

    func setSmooth(_ value: Bool) {
        defaults.set(value, forKey: Self.smoothKey)
    }

    var reverseVertical: Bool {
        defaults.object(forKey: Self.reverseVerticalKey) as? Bool ?? false
    }

    func setReverseVertical(_ value: Bool) {
        defaults.set(value, forKey: Self.reverseVerticalKey)
    }

    var reverseHorizontal: Bool {
        defaults.object(forKey: Self.reverseHorizontalKey) as? Bool ?? false
    }

    func setReverseHorizontal(_ value: Bool) {
        defaults.set(value, forKey: Self.reverseHorizontalKey)
    }

    var durationMs: Double {
        let value = defaults.object(forKey: Self.durationKey) as? Double
            ?? Self.defaultDurationMs
        return Self.clampDuration(value)
    }

    func setDurationMs(_ value: Double) {
        defaults.set(Self.clampDuration(value), forKey: Self.durationKey)
    }

    var gain: Double {
        let value = defaults.object(forKey: Self.gainKey) as? Double ?? Self.defaultGain
        return Self.clampGain(value)
    }

    func setGain(_ value: Double) {
        defaults.set(Self.clampGain(value), forKey: Self.gainKey)
    }

    var accelerationEnabled: Bool {
        defaults.object(forKey: Self.accelerationEnabledKey) as? Bool ?? true
    }

    func setAccelerationEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.accelerationEnabledKey)
    }

    var accelerationMax: Double {
        let value = defaults.object(forKey: Self.accelerationMaxKey) as? Double
            ?? Self.defaultAccelerationMax
        return Self.clampAccelerationMax(value)
    }

    func setAccelerationMax(_ value: Double) {
        defaults.set(Self.clampAccelerationMax(value), forKey: Self.accelerationMaxKey)
    }
}

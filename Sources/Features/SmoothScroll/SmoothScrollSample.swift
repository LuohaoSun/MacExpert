import CoreGraphics

// MARK: - 滚轮事件样本

/// 从 CGEvent 里抽出的纯值。分类、反向和平滑喂数都在这一层完成，
/// 这样滚轮方向的逻辑可以直接单元测试，不必造真实事件。
///
/// CGEvent 的轴编号：axis1 = 垂直（wheel1），axis2 = 水平（wheel2）。
struct ScrollSample: Equatable {

    var dxPoints: Double
    var dyPoints: Double
    var fixedDX: Double
    var fixedDY: Double
    var lineDeltaX: Int
    var lineDeltaY: Int
    var isContinuous: Bool
    var phase: Int
    var momentumPhase: Int
    var flags: CGEventFlags
    var targetPID: pid_t
    var sourceUserData: Int64

    init(
        dxPoints: Double = 0,
        dyPoints: Double = 0,
        fixedDX: Double? = nil,
        fixedDY: Double? = nil,
        lineDeltaX: Int = 0,
        lineDeltaY: Int = 0,
        isContinuous: Bool = false,
        phase: Int = 0,
        momentumPhase: Int = 0,
        flags: CGEventFlags = [],
        targetPID: pid_t = 0,
        sourceUserData: Int64 = 0
    ) {
        self.dxPoints = dxPoints
        self.dyPoints = dyPoints
        self.fixedDX = fixedDX ?? dxPoints
        self.fixedDY = fixedDY ?? dyPoints
        self.lineDeltaX = lineDeltaX
        self.lineDeltaY = lineDeltaY
        self.isContinuous = isContinuous
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.flags = flags
        self.targetPID = targetPID
        self.sourceUserData = sourceUserData
    }

    /// 相位才是手势设备的可靠标志。只看 isContinuous 会误伤
    /// 部分会发送连续事件的高分辨率滚轮鼠标。
    var isTrackpadLike: Bool { phase != 0 || momentumPhase != 0 }

    var hasDelta: Bool {
        dxPoints != 0 || dyPoints != 0 || fixedDX != 0 || fixedDY != 0
            || lineDeltaX != 0 || lineDeltaY != 0
    }

    /// 离散滚轮一行的名义距离，只用于把行增量换算成点。
    static let pointsPerLine: Double = 10

    /// 一格滚轮至少折算成这个距离。真实驱动经常只报 1 行甚至 1pt，
    /// 直接平滑会明显慢于系统原生滚动；33.6pt 接近 macOS 一格约三行的距离。
    static let minimumWheelStep: Double = 33.6

    var scrollDX: Double {
        Self.pixels(point: dxPoints, fixed: fixedDX, line: lineDeltaX, continuous: isContinuous)
    }

    var scrollDY: Double {
        Self.pixels(point: dyPoints, fixed: fixedDY, line: lineDeltaY, continuous: isContinuous)
    }

    private static func pixels(
        point: Double,
        fixed: Double,
        line: Int,
        continuous: Bool
    ) -> Double {
        let linePoints = Double(line) * pointsPerLine
        let raw: Double
        if point != 0 {
            if !continuous, abs(linePoints) > abs(point) {
                raw = linePoints
            } else {
                raw = point
            }
        } else if linePoints != 0 {
            raw = linePoints
        } else {
            raw = fixed
        }

        // 连续事件（高分辨率滚轮）保留原始细粒度增量；离散滚轮的小步长归一化，
        // 否则很多鼠标一格只报 1pt，平滑后几乎滚不动。
        guard !continuous, raw != 0, abs(raw) < minimumWheelStep else { return raw }
        return raw < 0 ? -minimumWheelStep : minimumWheelStep
    }

    var disposition: ScrollDisposition {
        if sourceUserData == ScrollMarker.value { return .passThrough(.ownEvent) }
        if isTrackpadLike { return .passThrough(.trackpadLike) }
        if flags.contains(.maskCommand) { return .passThrough(.command) }
        guard hasDelta else { return .passThrough(.noDelta) }
        return .takeOver
    }

    /// 只翻转指定轴。point / fixedPt / line 三种增量都要一起翻，
    /// 否则接收方可能按另一套字段读出没反向的值。
    func reversed(vertical: Bool, horizontal: Bool) -> ScrollSample {
        var copy = self
        if horizontal {
            copy.dxPoints = -dxPoints
            copy.fixedDX = -fixedDX
            copy.lineDeltaX = -lineDeltaX
        }
        if vertical {
            copy.dyPoints = -dyPoints
            copy.fixedDY = -fixedDY
            copy.lineDeltaY = -lineDeltaY
        }
        return copy
    }

    /// 事件的最终处理方案。`.modifyAndPass` 表示平滑关闭：在原事件上按指定轴
    /// 反向，然后立刻放行，不吞事件、不经过引擎，也没有倍率。
    func plan(
        smooth: Bool,
        reverseVertical: Bool,
        reverseHorizontal: Bool
    ) -> ScrollPlan {
        switch disposition {
        case .passThrough(let reason):
            return .passThrough(reason)
        case .takeOver:
            guard smooth else {
                return .modifyAndPass(
                    vertical: reverseVertical,
                    horizontal: reverseHorizontal
                )
            }
            let aimed = reversed(vertical: reverseVertical, horizontal: reverseHorizontal)
            return .swallowAndSmooth(dx: aimed.scrollDX, dy: aimed.scrollDY)
        }
    }
}

// MARK: - 分类结果

enum ScrollDisposition: Equatable {
    case passThrough(ScrollPassthrough)
    case takeOver
}

enum ScrollPassthrough: String, Equatable {
    case ownEvent
    case trackpadLike
    case command
    case noDelta

    var label: String {
        switch self {
        case .ownEvent: return "自身合成"
        case .trackpadLike: return "触控板/手势设备"
        case .command: return "⌘ 缩放"
        case .noDelta: return "无增量"
        }
    }
}

enum ScrollPlan: Equatable {
    case passThrough(ScrollPassthrough)
    /// 平滑关闭：原事件按指定轴反向（都为 false 时完全不改字段），随后原样放行。
    case modifyAndPass(vertical: Bool, horizontal: Bool)
    /// 平滑开启：吞掉原事件，把增量交给引擎。
    case swallowAndSmooth(dx: Double, dy: Double)
}

// MARK: - 常量

enum ScrollMarker {
    /// 合成事件的固定标记 "MXSS"，tap 看到它必须原样放行，防自激。
    static let value: Int64 = 0x4D_58_53_53
}

/// 合成事件使用的滚动相位值，和 CGEvent 的 scrollWheelEventScrollPhase 对应。
enum ScrollPhase: Int, Equatable {
    case began = 1
    case changed = 2
    case ended = 4
}

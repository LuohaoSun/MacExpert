import CoreGraphics

// MARK: - 合成滚轮事件

/// 引擎算出的整数增量在这里变成真正的 CGEvent。
///
/// 必须走 HID 全局投递：`CGEventPostToPid` 不经过窗口服务器的光标路由，
/// 事件虽然进了目标进程，但目标窗口不会滚动（实测 NSScrollView 完全不动）。
/// 全局投递由系统按当前光标位置路由，和真实滚轮一致。
final class ScrollPoster {

    /// 私有事件源：不要用 .hidSystemState，否则会污染真实 HID 的状态。
    private let source = CGEventSource(stateID: .privateState)

    func post(dx: Int, dy: Int, phase: ScrollPhase, flags: CGEventFlags) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: dy),
            wheel2: Int32(clamping: dx),
            wheel3: 0
        ) else { return }

        // 点增量用整数，固定点增量用 Double：一部分应用读的是后者。
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.flags = flags
        // 鼠标位置决定投递到哪个视图；不设的话会落在 (0,0)。
        if let location = CGEvent(source: nil)?.location {
            event.location = location
        }
        // tap 靠这个标记认出自己发出的事件，原样放行以免自激。
        event.setIntegerValueField(.eventSourceUserData, value: ScrollMarker.value)

        event.post(tap: .cghidEventTap)
    }
}

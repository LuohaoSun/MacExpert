import Foundation

/// 通用"绝对时刻时间表"播放器。
///
/// 把一串带绝对偏移的 Step 放到独立线程上按时刻执行: 睡到每个 step 的绝对时刻再调 action,
/// 期间每 20ms 轮询一次取消。不用 GCD 定时器逐事件调度——定时器截止时间会被合并/推迟,
/// 使相邻事件的间隔被吞掉; 手工按固定间隔逐个执行才稳定。
///
/// runId 语义由调用方注入(见 `isCurrent`): 播放器自己不维护 token, 避免和持有者各有一套
/// 互相不一致的运行编号。调用方通常直接传入"engine 当前的 runId 是否仍是本次"的闭包。
///
/// 线程模型:
/// - `play` 立即返回, 真正的执行在独立 Thread 上;
/// - `onProgress` 在主线程回调, 派发前与回调内都会再次确认 `isCurrent()`(过期就丢弃);
/// - `onFinish` 一定在主线程回调, 且一定会回调(包括被取消的情况)——是否要让过期 run 产生
///   副作用由调用方在 `onFinish` 里用 `isCurrent` 自行判断。
enum TimelinePlayer {

    /// 一个待执行事件。
    struct Step {
        /// 相对 `startedAt` 的绝对偏移(秒)。
        let offset: TimeInterval
        /// 时间轴日志用的标签。
        let label: String
        /// 非 nil 时上报进度值(含义由调用方定义, 例如"已敲入第 n 个字符")。
        let progress: Int?
        /// 真正要做的事。返回 false = 中止(不再执行后续 step)。
        let action: () -> Bool

        init(offset: TimeInterval, label: String = "", progress: Int? = nil, action: @escaping () -> Bool) {
            self.offset = offset
            self.label = label
            self.progress = progress
            self.action = action
        }
    }

    /// 播放结果。
    struct Result {
        /// 是否被中止(取消, 或某个 action 返回 false)。
        var aborted: Bool
        /// 成功执行的 step 数。
        var stepsExecuted: Int
        var stepsTotal: Int
        /// 从 `startedAt` 起算的耗时。
        var elapsed: TimeInterval
    }

    /// 在独立线程按绝对时刻播放 `steps`。
    ///
    /// - Parameters:
    ///   - steps: 按 offset 升序排好的事件。
    ///   - startedAt: 偏移基准时刻。
    ///   - tailPadding: 最后一个 step 之后再等多久才收尾(尾部余量, 由调用方决定)。
    ///   - isCurrent: 本次 run 是否仍然有效; 返回 false 时立即停止并丢弃后续进度。
    ///   - onProgress: 进度回调(主线程, 已确认 isCurrent)。
    ///   - onFinish: 结束回调(主线程, 一定回调; 过期 run 也回调, 便于落盘日志)。
    static func play(steps: [Step],
                     startedAt: Date,
                     tailPadding: TimeInterval,
                     isCurrent: @escaping () -> Bool,
                     onProgress: ((Int) -> Void)? = nil,
                     onFinish: @escaping (Result) -> Void) {
        let thread = Thread {
            var aborted = false
            var executed = 0

            for step in steps {
                guard sleep(until: startedAt.addingTimeInterval(step.offset), isCurrent: isCurrent) else {
                    aborted = true
                    break
                }
                guard step.action() else {
                    aborted = true
                    break
                }
                executed += 1
                if let n = step.progress, isCurrent() {
                    DispatchQueue.main.async {
                        guard isCurrent() else { return }
                        onProgress?(n)
                    }
                }
            }

            if !aborted, isCurrent(), let last = steps.last {
                // 所有事件执行完, 等尾部余量到点再收尾(时长含余量)。
                _ = sleep(until: startedAt.addingTimeInterval(last.offset + tailPadding), isCurrent: isCurrent)
            }

            let result = Result(aborted: aborted,
                                stepsExecuted: executed,
                                stepsTotal: steps.count,
                                elapsed: Date().timeIntervalSince(startedAt))
            DispatchQueue.main.async {
                onFinish(result)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.name = "MacExpert.TimelinePlayer"
        thread.start()
    }

    /// 睡到绝对时刻; 期间每 20ms 检查一次 `isCurrent`。返回 false 表示本次 run 已过期。
    @discardableResult
    static func sleep(until target: Date, isCurrent: () -> Bool) -> Bool {
        while true {
            if !isCurrent() { return false }
            let remain = target.timeIntervalSinceNow
            if remain <= 0 { return true }
            Thread.sleep(forTimeInterval: min(remain, 0.02))
        }
    }
}

import Darwin
import Foundation

// MARK: - 进程占用

/// 处理器详情里的单进程 CPU 占用。百分比按单核计算，可能超过 100%。
struct CPUProcessUsage: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let percent: Double

    var id: Int32 { pid }
}

/// 网络详情里的单进程吞吐，单位是字节/秒。
struct NetworkProcessUsage: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let download: Double
    let upload: Double

    var id: Int32 { pid }
}

// MARK: - CPU 进程采样

/// 只在处理器详情打开时采样。遍历当前用户的进程，读取累计 CPU 时间，
/// 用两次采样的差值算占用；读不到的进程直接跳过。
struct CPUProcessSampler {

    private var previous: [Int32: UInt64] = [:]
    private var previousTime: TimeInterval?
    private var names: [Int32: String] = [:]

    mutating func reset() {
        previous.removeAll()
        previousTime = nil
        names.removeAll()
    }

    mutating func sample(now: TimeInterval) -> [CPUProcessUsage]? {
        let elapsed = previousTime.map { now - $0 }
        guard let pids = Self.listPIDs() else { return nil }

        var current: [Int32: UInt64] = [:]
        current.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let info = Self.taskInfo(pid) else { continue }
            current[pid] = info.pti_total_user &+ info.pti_total_system
        }

        defer {
            previous = current
            previousTime = now
        }

        guard let elapsed, elapsed >= 0.2, !previous.isEmpty else { return nil }
        let previousSnapshot = previous

        var rows: [(pid: Int32, percent: Double)] = []
        for (pid, total) in current {
            guard let old = previousSnapshot[pid], total >= old else { continue }
            let deltaSeconds = Double(total - old)
                * Double(Self.timebase.numer)
                / Double(Self.timebase.denom)
                / 1_000_000_000
            let percent = deltaSeconds / elapsed * 100
            guard percent >= 0.05 else { continue }
            rows.append((pid, percent))
        }

        rows.sort { $0.percent > $1.percent }
        return rows.prefix(5).map { row in
            let name = names[row.pid] ?? Self.name(row.pid) ?? "PID \(row.pid)"
            names[row.pid] = name
            return CPUProcessUsage(pid: row.pid, name: name, percent: row.percent)
        }
    }

    /// `proc_taskinfo` 的 CPU 时间单位是 mach absolute time，
    /// Apple 芯片上不是纳秒（通常是 125/3 ns），必须用 timebase 转换。
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: libproc

    private static func listPIDs() -> [Int32]? {
        var capacity = 1024
        while capacity <= 65_536 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let bytes = Int32(capacity * MemoryLayout<pid_t>.stride)
            let count = proc_listallpids(&pids, bytes)
            guard count > 0 else { return nil }
            if Int(count) < capacity {
                return Array(pids.prefix(Int(count)))
            }
            capacity *= 2
        }
        return nil
    }

    private static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    static func name(_ pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let full = String(cString: path)
            let name = URL(fileURLWithPath: full).lastPathComponent
            if !name.isEmpty { return name }
        }

        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
        let value = String(cString: name)
        return value.isEmpty ? nil : value
    }
}

// MARK: - 网络进程采样

/// 把每个连接（NStat source）的累计字节换算成每秒速率。
/// 新连接的第一帧只记录基线；同一进程的多个连接会合并。
struct NetworkProcessRateTracker {

    private struct Flow {
        var pid: Int32
        var rx: Int64
        var tx: Int64
    }

    private struct Bytes {
        var rx: Int64 = 0
        var tx: Int64 = 0
    }

    private var flows: [UInt: Flow] = [:]
    private var names: [Int32: String] = [:]
    private var pending: [Int32: Bytes] = [:]

    mutating func rememberName(_ name: String, for pid: Int32) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        names[pid] = trimmed
    }

    mutating func update(flow id: UInt, pid: Int32, name: String, rx: Int64, tx: Int64) {
        rememberName(name, for: pid)

        if let previous = flows[id] {
            var bytes = pending[pid] ?? Bytes()
            bytes.rx += max(0, rx - previous.rx)
            bytes.tx += max(0, tx - previous.tx)
            pending[pid] = bytes
        }
        flows[id] = Flow(pid: pid, rx: rx, tx: tx)
    }

    mutating func remove(flow id: UInt) {
        flows.removeValue(forKey: id)
    }

    mutating func drain(elapsed: TimeInterval) -> [NetworkProcessUsage] {
        let seconds = max(elapsed, 0.2)
        let batch = pending
        pending.removeAll()
        guard !batch.isEmpty else { return [] }

        var rows: [NetworkProcessUsage] = []
        rows.reserveCapacity(batch.count)
        for (pid, bytes) in batch {
            guard bytes.rx + bytes.tx > 0 else { continue }
            rows.append(
                NetworkProcessUsage(
                    pid: pid,
                    name: names[pid] ?? CPUProcessSampler.name(pid) ?? "PID \(pid)",
                    download: Double(bytes.rx) / seconds,
                    upload: Double(bytes.tx) / seconds
                )
            )
        }

        rows.sort { ($0.download + $0.upload) > ($1.download + $1.upload) }
        return Array(rows.prefix(5))
    }

    mutating func reset() {
        flows.removeAll()
        names.removeAll()
        pending.removeAll()
    }
}

/// 用系统私有的 NetworkStatistics.framework 读取每个进程的累计收发字节。
/// `nettop -L` 的日志模式会持续占满一个多核心，这里改用框架的回调接口；
/// 只在网络详情打开时创建 manager，关闭就销毁。框架缺失时静默降级。
final class NetworkProcessSampler {

    static var isSupported: Bool {
        NetworkStatisticsAPI.shared != nil
    }

    private let api = NetworkStatisticsAPI.shared
    private let stateQueue = DispatchQueue(label: "com.slh.macexpert.monitor.nstat")
    private let lock = NSLock()
    private var tracker = NetworkProcessRateTracker()
    private var sources: [UInt: UnsafeMutableRawPointer] = [:]
    private var manager: UnsafeMutableRawPointer?
    private var timer: DispatchSourceTimer?
    private var lastTick = Date().timeIntervalSinceReferenceDate
    private var tickCount = 0
    private var generation = 0
    private var active = false
    private var onUpdate: (([NetworkProcessUsage]) -> Void)?

    func start(onUpdate: @escaping ([NetworkProcessUsage]) -> Void) {
        stop()
        guard let api else { return }

        active = true
        self.onUpdate = onUpdate
        lock.lock()
        tracker.reset()
        lastTick = Date().timeIntervalSinceReferenceDate
        tickCount = 0
        lock.unlock()

        let manager = api.create(kCFAllocatorDefault, stateQueue) { [weak self] source, _ in
            self?.attach(source)
        }
        guard let manager else {
            active = false
            self.onUpdate = nil
            return
        }
        self.manager = manager

        api.addAllTCP(manager)
        api.addAllUDP(manager)
        api.queryDescriptions(manager, {})

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        generation += 1
        active = false
        timer?.cancel()
        timer = nil
        if let manager, let api {
            api.destroy(manager)
        }
        manager = nil
        onUpdate = nil
        lock.lock()
        tracker.reset()
        sources.removeAll()
        tickCount = 0
        lock.unlock()
    }

    private func attach(_ source: UnsafeMutableRawPointer?) {
        guard let api, let source, active else { return }
        let flowID = UInt(bitPattern: UnsafeRawPointer(source))
        lock.lock()
        sources[flowID] = source
        lock.unlock()

        let description: @convention(block) (CFDictionary?) -> Void = { [weak self] dictionary in
            guard
                let self,
                let dictionary = dictionary as? [String: Any],
                let pid = (dictionary[api.keyPID] as? NSNumber)?.int32Value,
                pid > 0
            else { return }
            let name = dictionary[api.keyName] as? String ?? ""
            guard !name.isEmpty else { return }
            self.lock.lock()
            self.tracker.rememberName(name, for: pid)
            self.lock.unlock()
        }

        let counts: @convention(block) (CFDictionary?) -> Void = { [weak self] dictionary in
            guard
                let self,
                let dictionary = dictionary as? [String: Any],
                let pid = (dictionary[api.keyPID] as? NSNumber)?.int32Value,
                pid > 0
            else { return }
            let name = dictionary[api.keyName] as? String ?? ""
            let rx = (dictionary[api.keyRx] as? NSNumber)?.int64Value ?? 0
            let tx = (dictionary[api.keyTx] as? NSNumber)?.int64Value ?? 0
            self.lock.lock()
            self.tracker.update(flow: flowID, pid: pid, name: name, rx: rx, tx: tx)
            self.lock.unlock()
        }

        let removed: @convention(block) () -> Void = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.tracker.remove(flow: flowID)
            self.sources.removeValue(forKey: flowID)
            self.lock.unlock()
        }

        api.setDescription(source, description)
        api.setCounts(source, counts)
        api.setRemoved(source, removed)
        // 先取一次基线；之后的增量由每秒的 queryCounts 驱动。
        api.queryCounts(source)
    }

    private func tick() {
        guard active, let api, let onUpdate else { return }
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let elapsed = now - lastTick
        lastTick = now
        tickCount += 1
        let rows = tracker.drain(elapsed: elapsed)
        let ready = tickCount >= 2
        lock.unlock()

        // 第一秒只是在建立基线，先别急着告诉界面“没有活动”。
        if ready {
            onUpdate(rows)
        }

        // 查询和 source 移除都排在同一个串行队列上，避免查询已释放的 source。
        let generation = generation
        stateQueue.async { [weak self] in
            guard let self, self.active, self.generation == generation else { return }
            self.lock.lock()
            let sources = Array(self.sources.values)
            self.lock.unlock()
            for source in sources {
                api.queryCounts(source)
            }
        }
    }
}

// MARK: - NetworkStatistics 私有框架

/// `nettop` 和「活动监视器」用的就是这套接口。全部通过 dlsym 取符号，
/// 框架不存在或符号改名时返回 nil，不影响其他监控功能。
private struct NetworkStatisticsAPI {

    typealias ManagerRef = UnsafeMutableRawPointer
    typealias SourceRef = UnsafeMutableRawPointer

    typealias CreateFn = @convention(c) (
        CFAllocator?,
        dispatch_queue_t?,
        @escaping @convention(block) (SourceRef?, UnsafeMutableRawPointer?) -> Void
    ) -> ManagerRef?

    typealias AddAllFn = @convention(c) (ManagerRef?) -> Void
    typealias QueryFn = @convention(c) (
        ManagerRef?,
        @escaping @convention(block) () -> Void
    ) -> Void
    typealias DescriptionFn = @convention(c) (
        SourceRef?,
        @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void
    typealias CountsFn = DescriptionFn
    typealias RemovedFn = @convention(c) (
        SourceRef?,
        @escaping @convention(block) () -> Void
    ) -> Void
    typealias QueryCountsFn = @convention(c) (SourceRef?) -> Void
    typealias DestroyFn = @convention(c) (ManagerRef?) -> Void

    static let shared: NetworkStatisticsAPI? = NetworkStatisticsAPI()

    let create: CreateFn
    let addAllTCP: AddAllFn
    let addAllUDP: AddAllFn
    let queryDescriptions: QueryFn
    let setDescription: DescriptionFn
    let setCounts: CountsFn
    let setRemoved: RemovedFn
    let queryCounts: QueryCountsFn
    let destroy: DestroyFn

    let keyPID: String
    let keyName: String
    let keyRx: String
    let keyTx: String

    private init?() {
        let path = "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics"
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        func key(_ name: String) -> String? {
            guard let pointer = dlsym(handle, name) else { return nil }
            let value = pointer.assumingMemoryBound(to: CFString?.self).pointee
            return value as String?
        }

        guard
            let create = symbol("NStatManagerCreate", as: CreateFn.self),
            let addAllTCP = symbol("NStatManagerAddAllTCP", as: AddAllFn.self),
            let addAllUDP = symbol("NStatManagerAddAllUDP", as: AddAllFn.self),
            let queryDescriptions = symbol("NStatManagerQueryAllSourcesDescriptions", as: QueryFn.self),
            let setDescription = symbol("NStatSourceSetDescriptionBlock", as: DescriptionFn.self),
            let setCounts = symbol("NStatSourceSetCountsBlock", as: CountsFn.self),
            let setRemoved = symbol("NStatSourceSetRemovedBlock", as: RemovedFn.self),
            let queryCounts = symbol("NStatSourceQueryCounts", as: QueryCountsFn.self),
            let destroy = symbol("NStatManagerDestroy", as: DestroyFn.self),
            let keyPID = key("kNStatSrcKeyPID"),
            let keyName = key("kNStatSrcKeyProcessName"),
            let keyRx = key("kNStatSrcKeyRxBytes"),
            let keyTx = key("kNStatSrcKeyTxBytes")
        else {
            dlclose(handle)
            return nil
        }

        self.create = create
        self.addAllTCP = addAllTCP
        self.addAllUDP = addAllUDP
        self.queryDescriptions = queryDescriptions
        self.setDescription = setDescription
        self.setCounts = setCounts
        self.setRemoved = setRemoved
        self.queryCounts = queryCounts
        self.destroy = destroy
        self.keyPID = keyPID
        self.keyName = keyName
        self.keyRx = keyRx
        self.keyTx = keyTx
    }
}

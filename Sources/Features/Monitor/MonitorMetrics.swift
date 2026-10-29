import Darwin
import Foundation
import IOKit
import SystemConfiguration

// MARK: - 值模型

/// 一次 `host_statistics(HOST_CPU_LOAD_INFO)` 读到的累计 tick。
/// 系统给出的是 32 位计数，长时间运行会回绕，差值必须按无符号回绕计算。
struct CPUCounters: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32

    var total: UInt64 {
        UInt64(user) + UInt64(system) + UInt64(idle) + UInt64(nice)
    }
}

/// 某个网络接口在某一时刻的 64 位收发字节数。
struct NetworkCounters: Equatable {
    var interface: String
    var received: UInt64
    var sent: UInt64
}

/// 由两次网络采样得出的字节速率。
struct NetworkRate: Equatable {
    var download: Double
    var upload: Double
}

// MARK: - CPU

enum CPUMath {

    /// 两次累计 tick 求差，得到整机 CPU 占用率（0...100）。
    /// 第一次采样没有基线，返回 nil，界面上显示 `--`。
    static func utilization(previous: CPUCounters?, current: CPUCounters) -> Double? {
        guard let previous else { return nil }

        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let idle = UInt64(current.idle &- previous.idle)
        let nice = UInt64(current.nice &- previous.nice)

        let total = user + system + idle + nice
        guard total > 0 else { return nil }

        let busy = user + system + nice
        let value = Double(busy) / Double(total) * 100
        return min(max(value, 0), 100)
    }
}

/// 持有上一次 CPU tick 的采样器。睡眠唤醒后由外部调用 `reset()`。
struct CPUSampler {

    private var previous: CPUCounters?

    mutating func reset() {
        previous = nil
    }

    mutating func sample() -> Double? {
        guard let current = Self.readCounters() else { return nil }
        defer { previous = current }
        return CPUMath.utilization(previous: previous, current: current)
    }

    static func readCounters() -> CPUCounters? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return CPUCounters(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }
}

// MARK: - 网络

enum NetworkRateMath {

    /// 两次采样求速率。首样本、接口切换、计数回退、时间倒流都返回 nil，
    /// 调用方继续把当前计数记为下一次基线，从而避免睡眠或接口切换后的尖峰。
    static func rate(
        previous: NetworkCounters?,
        previousTime: TimeInterval?,
        current: NetworkCounters,
        currentTime: TimeInterval
    ) -> NetworkRate? {
        guard let previous, let previousTime else { return nil }
        guard previous.interface == current.interface else { return nil }

        let elapsed = currentTime - previousTime
        guard elapsed > 0, elapsed <= 60 else { return nil }
        guard current.received >= previous.received, current.sent >= previous.sent else {
            return nil
        }

        return NetworkRate(
            download: Double(current.received - previous.received) / elapsed,
            upload: Double(current.sent - previous.sent) / elapsed
        )
    }
}

enum NetworkReader {

    /// 系统当前的 primary interface（通常是有线或 Wi-Fi 的主用接口）。
    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MacExpertMonitor" as CFString, nil, nil) else {
            return nil
        }
        guard
            let value = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/IPv4" as CFString
            ) as? [String: Any]
        else {
            return nil
        }
        let name = value["PrimaryInterface"] as? String
        return (name?.isEmpty == false) ? name : nil
    }

    /// 读取指定接口的 64 位收发字节数。
    /// 走 `NET_RT_IFLIST2`，避开 `getifaddrs` 的 32 位计数回绕。
    static func counters(for interface: String) -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        let readResult = buffer.withUnsafeMutableBytes { raw in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &length, nil, 0)
        }
        guard readResult == 0, length > 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> NetworkCounters? in
            var offset = 0
            let limit = min(length, raw.count)

            while offset + MemoryLayout<if_msghdr2>.size <= limit {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength > 0 else { break }

                let messageType = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
                if messageType == UInt8(RTM_IFINFO2) {
                    let message = raw.loadUnaligned(
                        fromByteOffset: offset,
                        as: if_msghdr2.self
                    )
                    if let name = interfaceName(at: message.ifm_index), name == interface {
                        return NetworkCounters(
                            interface: name,
                            received: message.ifm_data.ifi_ibytes,
                            sent: message.ifm_data.ifi_obytes
                        )
                    }
                }

                offset += messageLength
            }
            return nil
        }
    }

    static func readPrimary() -> NetworkCounters? {
        guard let name = primaryInterface() else { return nil }
        return counters(for: name)
    }

    private static func interfaceName(at index: UInt16) -> String? {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        return String(cString: name)
    }
}

// MARK: - GPU

enum GPUUtilization {

    static let deviceKey = "Device Utilization %"
    static let rendererKey = "Renderer Utilization %"

    /// 优先读整体利用率，缺失时退回渲染器利用率，再缺失就返回 nil。
    /// 只读这两个百分比字段，不碰温度、功耗和频率。
    static func utilization(from statistics: [String: Any]) -> Double? {
        for key in [deviceKey, rendererKey] {
            guard let raw = statistics[key], let value = number(from: raw) else { continue }
            guard value.isFinite else { continue }
            return min(max(value, 0), 100)
        }
        return nil
    }

    private static func number(from value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }
}

struct GPUSampler {

    /// 从 IOKit 的 `IOAccelerator` 服务里读 `PerformanceStatistics`。
    /// Apple Silicon 上通常只有一个；找不到服务或字段就返回 nil。
    func sample() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { _ = IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                _ = IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            guard let property = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() else {
                continue
            }
            guard let statistics = property as? [String: Any] else { continue }
            if let value = GPUUtilization.utilization(from: statistics) {
                return value
            }
        }
        return nil
    }
}

// MARK: - 格式化

enum MonitorFormat {

    /// 菜单栏紧凑格式：`0B` / `512B` / `1.2K` / `12.4K` / `124K` / `1.2M` / `3.4G`。
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = sanitized(bytesPerSecond).rounded()
        guard value >= 1000 else { return "\(Int(value))B" }

        for unit in units where value >= unit.divisor {
            return scaled(value / unit.divisor) + unit.suffix
        }
        return "0B"
    }

    /// 页面上的完整格式，明确写出字节每秒。
    static func detailedRate(_ bytesPerSecond: Double) -> String {
        let value = sanitized(bytesPerSecond).rounded()
        guard value >= 1000 else { return "\(Int(value)) B/s" }

        for unit in units where value >= unit.divisor {
            return "\(scaled(value / unit.divisor)) \(unit.suffix)B/s"
        }
        return "0 B/s"
    }

    enum UsageLevel: Equatable {
        case normal
        case warning
        case critical
    }

    /// 百分比格式。没有数据时显示 `--`，与菜单栏保持一致。
    static func percent(_ value: Double?) -> String {
        guard let percent = percentValue(value) else { return "--" }
        return "\(percent)%"
    }

    /// 菜单栏着色阈值：显示 80% 起黄色，显示 100% 时红色。
    static func usageLevel(_ value: Double?) -> UsageLevel {
        guard let percent = percentValue(value) else { return .normal }
        if percent >= 100 { return .critical }
        if percent >= 80 { return .warning }
        return .normal
    }

    private static func percentValue(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(min(max(value, 0), 100).rounded())
    }

    private struct RateUnit {
        let divisor: Double
        let suffix: String
    }

    private static let units: [RateUnit] = [
        RateUnit(divisor: 1_000_000_000, suffix: "G"),
        RateUnit(divisor: 1_000_000, suffix: "M"),
        RateUnit(divisor: 1_000, suffix: "K"),
    ]

    private static func sanitized(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }

    /// 一位小数用于 1–99，三位有效数字附近用整数，避免字符串宽度跳动。
    private static func scaled(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

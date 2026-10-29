import AppKit
import Combine
import Foundation

// MARK: - 设置

/// 系统监控的用户设置。读取时统一夹到允许值，避免界面出现越界间隔。
struct MonitorStore {

    static let enabledKey = "monitor.enabled"
    static let showNetworkKey = "monitor.showNetwork"
    static let showCPUKey = "monitor.showCPU"
    static let intervalKey = "monitor.refreshInterval"

    static let allowedIntervals: [Double] = [1, 2, 5]
    static let defaultInterval: Double = 1

    static func clampInterval(_ value: Double) -> Double {
        allowedIntervals.min { abs($0 - value) < abs($1 - value) } ?? defaultInterval
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
    }

    var showNetwork: Bool {
        defaults.object(forKey: Self.showNetworkKey) as? Bool ?? true
    }

    func setShowNetwork(_ value: Bool) {
        defaults.set(value, forKey: Self.showNetworkKey)
    }

    var showCPU: Bool {
        defaults.object(forKey: Self.showCPUKey) as? Bool ?? true
    }

    func setShowCPU(_ value: Bool) {
        defaults.set(value, forKey: Self.showCPUKey)
    }

    var refreshInterval: Double {
        let value = defaults.object(forKey: Self.intervalKey) as? Double
            ?? Self.defaultInterval
        return Self.clampInterval(value)
    }

    func setRefreshInterval(_ value: Double) {
        defaults.set(Self.clampInterval(value), forKey: Self.intervalKey)
    }
}

// MARK: - 系统监控功能

/// 菜单栏的 CPU / 网络 / GPU 监控。
/// 采样全部走系统 API，只保留当前值；除了开关和间隔，不落任何监控数据。
final class MonitorFeature: ObservableObject {

    static let shared = MonitorFeature()

    private let store: MonitorStore
    private let gpuSampler = GPUSampler()

    private var cpuSampler = CPUSampler()
    private var previousNetwork: NetworkCounters?
    private var previousNetworkTime: TimeInterval?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var statusItems: MonitorStatusItems?
    private var installed = false
    private var isPreview = false

    @Published var enabled: Bool {
        didSet {
            guard !isPreview else { return }
            store.setEnabled(enabled)
            if enabled {
                startTimer()
                sampleNow()
            } else {
                stopTimer()
                resetReadings()
            }
            syncStatusItems()
        }
    }

    @Published var showNetwork: Bool {
        didSet {
            guard !isPreview else { return }
            store.setShowNetwork(showNetwork)
            syncStatusItems()
        }
    }

    @Published var showCPU: Bool {
        didSet {
            guard !isPreview else { return }
            store.setShowCPU(showCPU)
            syncStatusItems()
        }
    }

    @Published var refreshInterval: Double {
        didSet {
            let clamped = MonitorStore.clampInterval(refreshInterval)
            if clamped != refreshInterval {
                refreshInterval = clamped
                return
            }
            guard !isPreview else { return }
            store.setRefreshInterval(clamped)
            if timer != nil {
                stopTimer()
                startTimer()
            }
        }
    }

    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var gpuUsage: Double?
    @Published private(set) var primaryInterface: String?
    @Published private(set) var gpuSupported = true
    @Published private(set) var lastSample: Date?

    private init(store: MonitorStore = MonitorStore()) {
        self.store = store
        self.enabled = store.isEnabled
        self.showNetwork = store.showNetwork
        self.showCPU = store.showCPU
        self.refreshInterval = store.refreshInterval
    }

    // MARK: - 生命周期

    func install() {
        guard !installed else { return }
        installed = true
        guard !RuntimeFlags.isRenderingPreview else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        if enabled {
            startTimer()
            sampleNow()
        }
        syncStatusItems()
    }

    func shutdown() {
        stopTimer()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        removeStatusItems()
        resetReadings()
        installed = false
    }

    /// App 激活或页面打开时刷新一次当前值。
    func refreshNow() {
        sampleNow()
    }

    // MARK: - 采样

    func sampleNow() {
        guard enabled, installed, !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        let now = ProcessInfo.processInfo.systemUptime

        if let value = cpuSampler.sample() {
            cpuUsage = value
        }

        if let counters = NetworkReader.readPrimary() {
            primaryInterface = counters.interface
            if let rate = NetworkRateMath.rate(
                previous: previousNetwork,
                previousTime: previousNetworkTime,
                current: counters,
                currentTime: now
            ) {
                downloadRate = rate.download
                uploadRate = rate.upload
            } else if previousNetwork?.interface != counters.interface {
                downloadRate = 0
                uploadRate = 0
            }
            previousNetwork = counters
            previousNetworkTime = now
        } else {
            primaryInterface = nil
            previousNetwork = nil
            previousNetworkTime = nil
            downloadRate = 0
            uploadRate = 0
        }

        if let value = gpuSampler.sample() {
            gpuUsage = value
            gpuSupported = true
        } else {
            gpuUsage = nil
            gpuSupported = false
        }

        lastSample = Date()
        updateStatusItems()
    }

    private func handleWake() {
        guard enabled, installed, !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        cpuSampler.reset()
        previousNetwork = nil
        previousNetworkTime = nil
        cpuUsage = nil
        downloadRate = 0
        uploadRate = 0
        gpuUsage = nil
        sampleNow()
    }

    private func resetReadings() {
        cpuSampler.reset()
        previousNetwork = nil
        previousNetworkTime = nil
        downloadRate = 0
        uploadRate = 0
        cpuUsage = nil
        gpuUsage = nil
        primaryInterface = nil
        gpuSupported = true
        lastSample = nil
    }

    // MARK: - 定时器

    private func startTimer() {
        guard timer == nil, enabled, !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        let interval = refreshInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sampleNow()
        }
        timer.tolerance = min(0.25, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 菜单栏

    private func syncStatusItems() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        let shouldShow = enabled && (showNetwork || showCPU)
        guard shouldShow else {
            removeStatusItems()
            return
        }

        MainActor.assumeIsolated {
            let manager: MonitorStatusItems
            if let statusItems {
                manager = statusItems
            } else {
                let created = MonitorStatusItems { [weak self] in
                    self?.openMonitorPage()
                }
                statusItems = created
                manager = created
            }

            manager.setVisible(network: showNetwork, cpuGPU: showCPU)
            manager.update(
                download: downloadRate,
                upload: uploadRate,
                interface: primaryInterface,
                cpu: cpuUsage,
                gpu: gpuUsage
            )
        }
    }

    private func updateStatusItems() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        guard let statusItems else { return }

        MainActor.assumeIsolated {
            statusItems.update(
                download: downloadRate,
                upload: uploadRate,
                interface: primaryInterface,
                cpu: cpuUsage,
                gpu: gpuUsage
            )
        }
    }

    private func removeStatusItems() {
        guard let statusItems else { return }
        MainActor.assumeIsolated {
            statusItems.removeAll()
        }
        self.statusItems = nil
    }

    private func openMonitorPage() {
        MainActor.assumeIsolated {
            AppState.shared.open(.feature(.monitor))
            MainWindowController.shared.show()
        }
    }
}

// MARK: - 预览数据

#if MACEXPERT_DEV_HOOKS
extension MonitorFeature {

    /// 预览只填示例值，不启动定时器、不创建真实 status item。
    func applyPreviewData() {
        isPreview = true
        enabled = true
        showNetwork = true
        showCPU = true
        refreshInterval = MonitorStore.defaultInterval
        uploadRate = 1_240_000
        downloadRate = 3_400_000
        cpuUsage = 23
        gpuUsage = 45
        gpuSupported = true
        primaryInterface = "en0"
        lastSample = Date()
    }
}
#endif

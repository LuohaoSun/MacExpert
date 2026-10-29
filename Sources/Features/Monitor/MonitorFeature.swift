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

// MARK: - 详情状态

/// 菜单栏详情专用的高频状态。单独成对象，避免每秒写历史、每核占用和
/// Top 进程时，让只观察主状态的菜单栏和主窗口跟着重算。
final class MonitorDetailModel: ObservableObject {

    @Published var coreUsages: [Double] = []
    @Published var history = MonitorHistory()
    @Published var topCPUProcesses: [CPUProcessUsage] = []
    @Published var topNetworkProcesses: [NetworkProcessUsage] = []
    @Published var networkProcessesReady = false
    @Published var networkProcessesSupported = true

    func resetProcesses() {
        topCPUProcesses = []
        topNetworkProcesses = []
        networkProcessesReady = false
        networkProcessesSupported = true
    }

    func reset() {
        coreUsages = []
        history.clear()
        resetProcesses()
    }
}

// MARK: - 系统监控功能

/// 菜单栏的 CPU / 网络 / GPU 监控。
/// 采样全部走系统 API，只保留当前值；除了开关和间隔，不落任何监控数据。
final class MonitorFeature: ObservableObject {

    static let shared = MonitorFeature()

    let detail = MonitorDetailModel()

    private let store: MonitorStore
    private let gpuSampler = GPUSampler()

    private var cpuSampler = CPUSampler()
    private var coreSampler = CPUCoreSampler()
    private var cpuProcessSampler = CPUProcessSampler()
    private let networkProcessSampler = NetworkProcessSampler()
    private var previousNetwork: NetworkCounters?
    private var previousNetworkTime: TimeInterval?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var statusItems: MonitorStatusItems?
    private var popoverController: MonitorPopoverController?
    private var detailKind: MonitorStatusKind?
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

    /// 打开某个菜单栏详情。Top 进程只在详情打开期间采样。
    func beginDetail(_ kind: MonitorStatusKind) {
        MainActor.assumeIsolated {
            endDetail()
            detailKind = kind
            switch kind {
            case .processor:
                cpuProcessSampler.reset()
                detail.topCPUProcesses = []
                refreshNow()
            case .network:
                detail.topNetworkProcesses = []
                detail.networkProcessesReady = false
                detail.networkProcessesSupported = NetworkProcessSampler.isSupported
                guard detail.networkProcessesSupported else { return }
                networkProcessSampler.start { [weak self] rows in
                    guard let self else { return }
                    self.detail.topNetworkProcesses = rows
                    self.detail.networkProcessesReady = true
                }
            }
        }
    }

    func endDetail() {
        MainActor.assumeIsolated {
            detailKind = nil
            detail.resetProcesses()
            networkProcessSampler.stop()
            cpuProcessSampler.reset()
        }
    }

    // MARK: - 采样

    func sampleNow() {
        guard enabled, installed, !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        let now = ProcessInfo.processInfo.systemUptime

        if let value = cpuSampler.sample() {
            cpuUsage = value
        }

        if let cores = coreSampler.sample() {
            detail.coreUsages = cores
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

        detail.history.append(
            cpu: cpuUsage,
            gpu: gpuUsage,
            download: downloadRate,
            upload: uploadRate
        )

        if detailKind == .processor, let rows = cpuProcessSampler.sample(now: now) {
            detail.topCPUProcesses = rows
        }

        lastSample = Date()
        updateStatusItems()
    }

    private func handleWake() {
        guard enabled, installed, !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        cpuSampler.reset()
        coreSampler.reset()
        previousNetwork = nil
        previousNetworkTime = nil
        cpuUsage = nil
        detail.coreUsages = []
        detail.history.clear()
        downloadRate = 0
        uploadRate = 0
        gpuUsage = nil
        sampleNow()
    }

    private func resetReadings() {
        cpuSampler.reset()
        coreSampler.reset()
        cpuProcessSampler.reset()
        networkProcessSampler.stop()
        detailKind = nil
        previousNetwork = nil
        previousNetworkTime = nil
        downloadRate = 0
        uploadRate = 0
        cpuUsage = nil
        gpuUsage = nil
        detail.reset()
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
            MainActor.assumeIsolated {
                popoverController?.close()
            }
            removeStatusItems()
            return
        }

        MainActor.assumeIsolated {
            let manager: MonitorStatusItems
            if let statusItems {
                manager = statusItems
            } else {
                let created = MonitorStatusItems { [weak self] kind, button in
                    self?.togglePopover(relativeTo: button, kind: kind)
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
            popoverController?.close()
            statusItems.removeAll()
        }
        self.statusItems = nil
    }

    private func togglePopover(relativeTo button: NSStatusBarButton, kind: MonitorStatusKind) {
        MainActor.assumeIsolated {
            if popoverController == nil {
                popoverController = MonitorPopoverController { [weak self] in
                    self?.openMonitorPage()
                }
            }
            popoverController?.toggle(relativeTo: button, kind: kind)
        }
    }

    private func openMonitorPage() {
        MainActor.assumeIsolated {
            popoverController?.close()
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
        detail.coreUsages = [18, 24, 30, 12, 8, 45, 50, 20]
        detail.history.clear()
        for index in 0..<MonitorHistory.capacity {
            let phase = Double(index) / Double(MonitorHistory.capacity) * .pi * 2
            detail.history.append(
                cpu: 28 + sin(phase) * 18,
                gpu: 45 + cos(phase) * 12,
                download: 3_400_000 + sin(phase * 2) * 900_000,
                upload: 1_240_000 + cos(phase * 2) * 300_000
            )
        }
        gpuSupported = true
        primaryInterface = "en0"
        lastSample = Date()
        detail.topCPUProcesses = [
            CPUProcessUsage(pid: 1445, name: "ZCode", percent: 28),
            CPUProcessUsage(pid: 979, name: "WeChat", percent: 12),
            CPUProcessUsage(pid: 969, name: "企业微信", percent: 8),
            CPUProcessUsage(pid: 2250, name: "verge-mihomo", percent: 5),
            CPUProcessUsage(pid: 514, name: "mDNSResponder", percent: 2),
        ]
        detail.topNetworkProcesses = [
            NetworkProcessUsage(pid: 2250, name: "verge-mihomo", download: 2_400_000, upload: 320_000),
            NetworkProcessUsage(pid: 1445, name: "ZCode", download: 180_000, upload: 24_000),
            NetworkProcessUsage(pid: 969, name: "企业微信", download: 96_000, upload: 8_000),
            NetworkProcessUsage(pid: 979, name: "WeChat", download: 42_000, upload: 12_000),
            NetworkProcessUsage(pid: 514, name: "mDNSResponder", download: 8_000, upload: 2_000),
        ]
        detail.networkProcessesReady = true
        detail.networkProcessesSupported = true
    }

    /// 仅开发验证：不合成鼠标事件，直接展示真实 NSPopover。
    @MainActor
    func showPopoverForTesting(kind: MonitorStatusKind = .processor) {
        guard let button = statusItems?.buttonForPreview else { return }
        togglePopover(relativeTo: button, kind: kind)
    }
}
#endif

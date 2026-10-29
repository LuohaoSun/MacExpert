import AppKit
import SwiftUI

// MARK: - 菜单栏详情弹窗

/// 点击菜单栏监控项后展开的详情。处理器和网络各自独立，
/// Top 进程只在对应弹窗打开期间采样。
struct MonitorPopoverView: View {

    @ObservedObject var monitor: MonitorFeature
    @ObservedObject var detail: MonitorDetailModel
    let kind: MonitorStatusKind
    var onOpenMonitor: () -> Void

    static func contentHeight(for kind: MonitorStatusKind) -> CGFloat {
        switch kind {
        case .processor:
            return 540
        case .network:
            return 430
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch kind {
                    case .processor:
                        processorSections
                    case .network:
                        networkSections
                    }
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: Self.contentHeight(for: kind))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(monitor.enabled ? Theme.green : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(kind == .processor ? "处理器详情" : "网络详情")
                .font(.headline)

            Spacer(minLength: 8)

            if let lastSample = monitor.lastSample {
                Text(lastSample, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("等待采样")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 处理器

    @ViewBuilder
    private var processorSections: some View {
        usageSection
        coreSection
        processorHistorySection
        topCPUProcessesSection
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("处理器")
            HStack(spacing: 10) {
                usageTile("CPU", monitor.cpuUsage)
                usageTile("GPU", monitor.gpuUsage)
            }
        }
    }

    private func usageTile(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(MonitorFormat.percent(value))
                    .font(.system(size: 21, weight: .semibold).monospacedDigit())
                    .foregroundStyle(usageColor(value))
            }

            ProgressView(value: min(max(value ?? 0, 0), 100), total: 100)
                .tint(barColor(value))
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                sectionTitle("每核 CPU")
                Spacer(minLength: 4)
                if !detail.coreUsages.isEmpty {
                    Text("\(detail.coreUsages.count) 核")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if detail.coreUsages.isEmpty {
                Text("等待采样…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 26, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 7
                ) {
                    ForEach(detail.coreUsages.indices, id: \.self) { index in
                        coreCell(index: index, value: detail.coreUsages[index])
                    }
                }
            }
        }
    }

    private func coreCell(index: Int, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text("\(index + 1)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(min(max(value, 0), 100).rounded()))%")
                    .font(.system(size: 8.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(usageColor(value))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(barColor(value))
                        .frame(
                            width: geometry.size.width
                                * min(max(value, 0), 100) / 100
                        )
                }
            }
            .frame(height: 3)
        }
    }

    private var processorHistorySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                sectionTitle("最近 \(MonitorHistory.capacity) 次采样")
                Spacer(minLength: 4)
                legendDot("CPU", color: Theme.accent)
                legendDot("GPU", color: Theme.green)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                Sparkline(values: detail.history.cpu, maximum: 100, color: Theme.accent)
                Sparkline(values: detail.history.gpu, maximum: 100, color: Theme.green)
            }
            .frame(height: 58)

            if !monitor.gpuSupported {
                Text("当前系统未提供 GPU 利用率。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topCPUProcessesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionTitle("占用最高的进程")
                Spacer(minLength: 4)
                Text("CPU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if detail.topCPUProcesses.isEmpty {
                Text("正在采样…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 54, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detail.topCPUProcesses.enumerated()), id: \.element.id) { index, row in
                        processRow(
                            index: index,
                            name: row.name,
                            value: String(format: "%.0f%%", row.percent),
                            color: usageColor(row.percent)
                        )
                    }
                }
            }
        }
    }

    // MARK: 网络

    @ViewBuilder
    private var networkSections: some View {
        networkSummarySection
        networkHistorySection
        topNetworkProcessesSection
    }

    private var networkSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionTitle("实时速率")
                Spacer(minLength: 4)
                if let interface = monitor.primaryInterface {
                    Badge(text: interface, color: Theme.accent)
                } else {
                    Badge(text: "未连接", color: .secondary)
                }
            }

            HStack(spacing: 10) {
                networkTile(
                    "上传",
                    MonitorFormat.detailedRate(monitor.uploadRate),
                    color: .orange,
                    systemImage: "arrow.up"
                )
                networkTile(
                    "下载",
                    MonitorFormat.detailedRate(monitor.downloadRate),
                    color: .blue,
                    systemImage: "arrow.down"
                )
            }
        }
    }

    private func networkTile(
        _ title: String,
        _ value: String,
        color: Color,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var networkHistorySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                sectionTitle("最近 \(MonitorHistory.capacity) 次采样")
                Spacer(minLength: 4)
                legendDot("上传", color: .orange)
                legendDot("下载", color: .blue)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                Sparkline(
                    values: detail.history.download,
                    maximum: networkMaximum,
                    color: .blue
                )
                Sparkline(
                    values: detail.history.upload,
                    maximum: networkMaximum,
                    color: .orange
                )
            }
            .frame(height: 58)
        }
    }

    private var networkMaximum: Double {
        max(
            detail.history.download.max() ?? 0,
            detail.history.upload.max() ?? 0,
            1
        )
    }

    private var topNetworkProcessesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionTitle("占用最高的进程")
                Spacer(minLength: 4)
                Text("网络")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !detail.networkProcessesSupported {
                Text("当前系统无法读取进程流量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 54, alignment: .leading)
            } else if !detail.networkProcessesReady {
                Text("正在采样…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 54, alignment: .leading)
            } else if detail.topNetworkProcesses.isEmpty {
                Text("最近 1 秒没有网络活动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 54, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detail.topNetworkProcesses.enumerated()), id: \.element.id) { index, row in
                        networkProcessRow(index: index, row: row)
                    }
                }
            }
        }
    }

    private func networkProcessRow(index: Int, row: NetworkProcessUsage) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)

            Text(row.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Text("↓ \(MonitorFormat.compactRate(row.download))")
                    .foregroundStyle(.blue)
                Text("↑ \(MonitorFormat.compactRate(row.upload))")
                    .foregroundStyle(.orange)
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .lineLimit(1)
        }
        .frame(height: 22)
    }

    // MARK: 进程行

    private func processRow(
        index: Int,
        name: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)

            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(height: 22)
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text("每 \(Int(monitor.refreshInterval)) 秒刷新")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("打开监控页", action: onOpenMonitor)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 小工具

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func usageColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch MonitorFormat.usageLevel(value) {
        case .normal:
            return .primary
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }

    /// 进度条在正常区间用强调色，高占用时才切到黄/红。
    private func barColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch MonitorFormat.usageLevel(value) {
        case .normal:
            return Theme.accent
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }
}

// MARK: - 折线

private struct Sparkline: View {

    let values: [Double]
    let maximum: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1 else { return }
                let upper = max(maximum, 1)
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width
                        * CGFloat(index) / CGFloat(values.count - 1)
                    let normalized = min(max(value, 0), upper) / upper
                    let y = geometry.size.height * (1 - CGFloat(normalized))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .padding(7)
        .accessibilityHidden(true)
    }
}

// MARK: - 弹窗控制

@MainActor
final class MonitorPopoverController: NSObject, NSPopoverDelegate {

    private let popover = NSPopover()
    private let onOpenMonitor: () -> Void

    init(onOpenMonitor: @escaping () -> Void) {
        self.onOpenMonitor = onOpenMonitor
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func toggle(relativeTo button: NSStatusBarButton, kind: MonitorStatusKind) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        MonitorFeature.shared.beginDetail(kind)

        let view = MonitorPopoverView(
            monitor: .shared,
            detail: MonitorFeature.shared.detail,
            kind: kind
        ) { [weak self] in
            self?.close()
            self?.onOpenMonitor()
        }
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = NSSize(
            width: 340,
            height: MonitorPopoverView.contentHeight(for: kind)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if !popover.isShown {
            MonitorFeature.shared.endDetail()
        }
    }

    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        MonitorFeature.shared.endDetail()
    }
}

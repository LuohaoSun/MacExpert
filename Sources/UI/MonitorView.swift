import SwiftUI

/// 主窗口里的「系统监控」页。
struct MonitorView: View {

    @ObservedObject private var monitor = MonitorFeature.shared

    var body: some View {
        PageScaffold {
            statusCard
            menuBarCard
            liveCard
            samplingCard
            privacyCard
        }
        .onAppear { monitor.refreshNow() }
    }

    // MARK: - 状态

    private var statusCard: some View {
        CardSurface {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.enabled ? "系统监控已启用" : "系统监控已关闭")
                        .font(.headline)
                    Text(
                        monitor.enabled
                            ? "菜单栏显示网速、CPU 与 GPU；全部数据只在本机读取。"
                            : "关闭后停止采样，并移除两个菜单栏项目。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Text("启用")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("启用系统监控")
                }
                .fixedSize()
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(monitor.enabled ? Theme.green : Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(x: -10, y: 8)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - 菜单栏

    private var menuBarCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("菜单栏")
                    .font(.headline)

                SettingsRow(
                    "网络速率",
                    detail: "上行 / 下行两行显示，固定宽度"
                ) {
                    Toggle("", isOn: showNetworkBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("在菜单栏显示网络速率")
                }

                SettingsRow(
                    "CPU / GPU",
                    detail: "两行显示 CPU 与 GPU 利用率"
                ) {
                    Toggle("", isOn: showCPUBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("在菜单栏显示 CPU 与 GPU")
                }

                Divider()

                HStack(alignment: .center, spacing: 14) {
                    menuBarPreviewItem(
                        width: MonitorStatusItems.networkWidth,
                        top: MenuBarPreviewLine(
                            prefix: "↑",
                            value: MonitorFormat.compactRate(monitor.uploadRate),
                            color: .primary
                        ),
                        bottom: MenuBarPreviewLine(
                            prefix: "↓",
                            value: MonitorFormat.compactRate(monitor.downloadRate),
                            color: .primary
                        ),
                        visible: monitor.showNetwork
                    )

                    menuBarPreviewItem(
                        width: MonitorStatusItems.cpuWidth,
                        top: MenuBarPreviewLine(
                            prefix: "C",
                            value: MonitorFormat.percent(monitor.cpuUsage),
                            color: .primary
                        ),
                        bottom: MenuBarPreviewLine(
                            prefix: "G",
                            value: MonitorFormat.percent(monitor.gpuUsage),
                            color: .primary
                        ),
                        visible: monitor.showCPU
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("菜单栏预览")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("固定宽度 · 等宽数字")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .opacity(monitor.enabled ? 1 : 0.45)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(menuBarPreviewAccessibility)
            }
        }
    }

    private struct MenuBarPreviewLine {
        let prefix: String
        let value: String
        let color: Color
    }

    private func menuBarPreviewItem(
        width: CGFloat,
        top: MenuBarPreviewLine,
        bottom: MenuBarPreviewLine,
        visible: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            previewLine(top)
            previewLine(bottom)
        }
        .padding(.leading, 7)
        .frame(width: width, height: 26, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .opacity(visible ? 1 : 0.35)
        .help(visible ? "菜单栏中显示" : "菜单栏中已隐藏")
    }

    private func previewLine(_ line: MenuBarPreviewLine) -> some View {
        HStack(spacing: 2) {
            Text(line.prefix)
                .foregroundStyle(line.color)
            Text(line.value)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 9.5, weight: .regular))
        .frame(height: 13, alignment: .leading)
    }

    private var menuBarPreviewAccessibility: String {
        let upload = MonitorFormat.detailedRate(monitor.uploadRate)
        let download = MonitorFormat.detailedRate(monitor.downloadRate)
        let cpu = MonitorFormat.percent(monitor.cpuUsage)
        let gpu = MonitorFormat.percent(monitor.gpuUsage)
        return "菜单栏预览：上传 \(upload)，下载 \(download)；CPU \(cpu)，GPU \(gpu)"
    }

    // MARK: - 实时状态

    private var liveCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("实时状态")
                        .font(.headline)

                    Spacer(minLength: 8)

                    if let interface = monitor.primaryInterface {
                        Badge(text: interface, color: Theme.accent)
                    } else {
                        Badge(text: "未连接", color: .secondary)
                    }
                }

                HStack(spacing: 10) {
                    metricTile(
                        "上传",
                        MonitorFormat.detailedRate(monitor.uploadRate),
                        color: .orange
                    )
                    metricTile(
                        "下载",
                        MonitorFormat.detailedRate(monitor.downloadRate),
                        color: .blue
                    )
                    metricTile(
                        "CPU",
                        MonitorFormat.percent(monitor.cpuUsage),
                        color: Theme.green
                    )
                    metricTile(
                        "GPU",
                        MonitorFormat.percent(monitor.gpuUsage),
                        color: .purple
                    )
                }

                if !monitor.gpuSupported {
                    Text("当前系统未提供 GPU 利用率。MacExpert 只读取 IOAccelerator 的利用率字段，不读取温度、功耗或频率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("网络按系统 primary interface 统计，单位是字节/秒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricTile(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - 采样

    private var samplingCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("采样")
                    .font(.headline)

                SettingsRow(
                    "刷新间隔",
                    detail: "菜单栏和本页共用这个频率"
                ) {
                    Picker("刷新间隔", selection: intervalBinding) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("5 秒").tag(5.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .accessibilityLabel("刷新间隔")
                }
            }
        }
    }

    // MARK: - 隐私

    private var privacyCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label("隐私", systemImage: "lock.shield")
                    .font(.headline)

                privacyLine("全部数据在本机采集，只保存在内存和当前页面。")
                privacyLine("不记录网络内容，不发送任何网络请求。")
                privacyLine("只读系统计数器和 GPU 利用率，不需要辅助功能权限，也不需要 root。")
            }
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.green)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 绑定

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.enabled },
            set: { monitor.enabled = $0 }
        )
    }

    private var showNetworkBinding: Binding<Bool> {
        Binding(
            get: { monitor.showNetwork },
            set: { monitor.showNetwork = $0 }
        )
    }

    private var showCPUBinding: Binding<Bool> {
        Binding(
            get: { monitor.showCPU },
            set: { monitor.showCPU = $0 }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { monitor.refreshInterval },
            set: { monitor.refreshInterval = $0 }
        )
    }
}

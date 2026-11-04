import SwiftUI

/// 主窗口里的「系统监控」页。
struct MonitorView: View {

    @ObservedObject private var monitor = MonitorFeature.shared

    var body: some View {
        PageScaffold {
            statusCard
            menuBarCard
                .disabled(!monitor.enabled)
                .opacity(monitor.enabled ? 1 : 0.45)
            samplingCard
                .disabled(!monitor.enabled)
                .opacity(monitor.enabled ? 1 : 0.45)
            privacyCard
        }
    }

    // MARK: - 状态

    private var statusCard: some View {
        CardSurface {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.enabled ? "系统监控已启用" : "系统监控已关闭")
                        .font(.headline)
                    Text(statusSubtitle)
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

    private var statusSubtitle: String {
        guard monitor.enabled else {
            return "已停止采样，并不在菜单栏显示监控项。"
        }
        if !monitor.showNetwork && !monitor.showCPU {
            return "已启用监控，但两个菜单栏显示项均已关闭。"
        }
        if monitor.showNetwork && !monitor.showCPU {
            return "菜单栏正在显示网络速率；全部数据仅在本机读取。"
        }
        if !monitor.showNetwork && monitor.showCPU {
            return "菜单栏正在显示 CPU 与 GPU 利用率；全部数据仅在本机读取。"
        }
        return "菜单栏正在显示网络速率与 CPU / GPU 利用率；全部数据仅在本机读取。"
    }

    // MARK: - 菜单栏

    private var menuBarCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("菜单栏")
                    .font(.headline)

                SettingsRow(
                    "网络速率",
                    detail: "上下两行显示实时上传与下载速率，宽度固定不跳动"
                ) {
                    Toggle("", isOn: showNetworkBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("在菜单栏显示网络速率")
                }

                SettingsRow(
                    "CPU / GPU",
                    detail: "上下两行显示处理器与图形处理器总利用率"
                ) {
                    Toggle("", isOn: showCPUBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("在菜单栏显示 CPU 与 GPU")
                }

                Text("点击菜单栏中的网络或 CPU/GPU 图标，可分别展开对应的历史曲线与高占用进程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 采样

    private var samplingCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("采样")
                    .font(.headline)

                SettingsRow(
                    "采样间隔",
                    detail: "菜单栏数值与详情弹窗共用此采样频率"
                ) {
                    Picker("采样间隔", selection: intervalBinding) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("5 秒").tag(5.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .accessibilityLabel("采样间隔")
                }
            }
        }
    }

    // MARK: - 隐私

    private var privacyCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("隐私")
                    .font(.headline)

                privacyLine("全部数据在本机采集，只保存在内存和菜单栏详情中。")
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

import AppKit

// MARK: - 两个菜单栏项目

/// 网络与 CPU/GPU 两个独立的 `NSStatusItem`。
/// 每个 item 内部是固定宽度的双行视图，数值变化不会推动菜单栏其他项目。
@MainActor
final class MonitorStatusItems: NSObject {

    static let networkWidth: CGFloat = 43
    static let cpuWidth: CGFloat = 40

    /// item 左右各留 2pt；宽度按两行里较长的一行计算。
    static func width(for lines: [String]) -> CGFloat {
        let font = MonitorTwoLineStatusView.font
        let textWidth = lines
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(textWidth) + 4
    }

    private let networkView = MonitorTwoLineStatusView(leadingInset: 2)
    private let cpuView = MonitorTwoLineStatusView(leadingInset: 2)
    private let onSelect: () -> Void

    private var networkItem: NSStatusItem?
    private var cpuItem: NSStatusItem?

    init(onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        super.init()
    }

    // MARK: - 创建与移除

    func setVisible(network: Bool, cpuGPU: Bool) {
        if network {
            if networkItem == nil {
                networkItem = makeItem(
                    length: Self.networkWidth,
                    view: networkView,
                    accessibility: "网络监控"
                )
            }
        } else {
            removeNetworkItem()
        }

        if cpuGPU {
            if cpuItem == nil {
                cpuItem = makeItem(
                    length: Self.cpuWidth,
                    view: cpuView,
                    accessibility: "CPU 与 GPU 监控"
                )
            }
        } else {
            removeCPUItem()
        }
    }

    func removeAll() {
        removeNetworkItem()
        removeCPUItem()
    }

    // MARK: - 内容

    func update(
        download: Double,
        upload: Double,
        interface: String?,
        cpu: Double?,
        gpu: Double?
    ) {
        let uploadDetail = MonitorFormat.detailedRate(upload)
        let downloadDetail = MonitorFormat.detailedRate(download)
        let interfaceName = interface ?? "未连接"
        let uploadText = MonitorFormat.compactRate(upload)
        let downloadText = MonitorFormat.compactRate(download)
        let cpuText = MonitorFormat.percent(cpu)
        let gpuText = MonitorFormat.percent(gpu)

        networkView.setTop(prefix: "↑", value: uploadText, color: .labelColor)
        networkView.setBottom(prefix: "↓", value: downloadText, color: .labelColor)
        networkItem?.length = Self.width(for: ["↑ \(uploadText)", "↓ \(downloadText)"])
        setAccessibility(
            on: networkItem,
            text: "网络：上传 \(uploadDetail)，下载 \(downloadDetail)（\(interfaceName)）"
        )

        cpuView.setTop(prefix: "C", value: cpuText, color: Self.usageColor(cpu))
        cpuView.setBottom(prefix: "G", value: gpuText, color: Self.usageColor(gpu))
        cpuItem?.length = Self.width(for: ["C \(cpuText)", "G \(gpuText)"])
        let gpuAccessibility = gpu == nil ? "GPU 不可用" : "GPU \(gpuText)"
        setAccessibility(
            on: cpuItem,
            text: "CPU \(cpuText)，\(gpuAccessibility)"
        )
    }

    // MARK: - 私有

    private static func usageColor(_ value: Double?) -> NSColor {
        switch MonitorFormat.usageLevel(value) {
        case .normal:
            return .labelColor
        case .warning:
            return .systemYellow
        case .critical:
            return .systemRed
        }
    }

    private func makeItem(
        length: CGFloat,
        view: NSView,
        accessibility: String
    ) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        guard let button = item.button else { return item }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(clicked(_:))
        button.toolTip = accessibility
        button.setAccessibilityLabel(accessibility)
        button.setAccessibilityHelp(accessibility)

        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        return item
    }

    private func setAccessibility(on item: NSStatusItem?, text: String) {
        guard let button = item?.button else { return }
        button.toolTip = text
        button.setAccessibilityLabel(text)
        button.setAccessibilityHelp(text)
    }

    private func removeNetworkItem() {
        guard let networkItem else { return }
        NSStatusBar.system.removeStatusItem(networkItem)
        networkView.removeFromSuperview()
        self.networkItem = nil
    }

    private func removeCPUItem() {
        guard let cpuItem else { return }
        NSStatusBar.system.removeStatusItem(cpuItem)
        cpuView.removeFromSuperview()
        self.cpuItem = nil
    }

    @objc private func clicked(_ sender: Any?) {
        onSelect()
    }
}

// MARK: - 双行视图

/// 菜单栏 item 里的两行文字。点击必须穿透到 status item 的 button，
/// 所以 `hitTest` 固定返回 nil。
final class MonitorTwoLineStatusView: NSView {

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

    private let leadingInset: CGFloat
    private let topLabel = MonitorTwoLineStatusView.makeLabel()
    private let bottomLabel = MonitorTwoLineStatusView.makeLabel()

    init(leadingInset: CGFloat) {
        self.leadingInset = leadingInset
        super.init(frame: .zero)
        addSubview(topLabel)
        addSubview(bottomLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()

        // 两行文字按 10pt 行距居中，比均分按钮高度更紧凑。
        let lineHeight = min(11, bounds.height)
        let pitch = max(0, lineHeight - 1)
        let width = max(0, bounds.width - leadingInset - 2)
        topLabel.frame = NSRect(
            x: leadingInset,
            y: bounds.midY + pitch / 2 - lineHeight / 2,
            width: width,
            height: lineHeight
        )
        bottomLabel.frame = NSRect(
            x: leadingInset,
            y: bounds.midY - pitch / 2 - lineHeight / 2,
            width: width,
            height: lineHeight
        )
    }

    func setTop(prefix: String, value: String, color: NSColor) {
        topLabel.attributedStringValue = makeLine(prefix: prefix, value: value, color: color)
    }

    func setBottom(prefix: String, value: String, color: NSColor) {
        bottomLabel.attributedStringValue = makeLine(prefix: prefix, value: value, color: color)
    }

    private func makeLine(prefix: String, value: String, color: NSColor) -> NSAttributedString {
        let font = Self.font
        let text = NSMutableAttributedString(
            string: prefix,
            attributes: [.font: font, .foregroundColor: color]
        )
        text.append(
            NSAttributedString(
                string: " \(value)",
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
        )
        return text
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = .labelColor
        label.alignment = .left
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.isSelectable = false
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.cell?.usesSingleLineMode = true
        return label
    }
}

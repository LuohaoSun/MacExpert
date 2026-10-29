import AppKit

// MARK: - 两个菜单栏项目

/// 点击的是哪一个菜单栏项目，决定详情弹窗显示处理器还是网络。
enum MonitorStatusKind: Equatable {
    case processor
    case network
}

/// 网络与 CPU/GPU 两个独立的 `NSStatusItem`。
/// 每个 item 内部是固定宽度的双行视图，数值变化不会推动菜单栏其他项目。
@MainActor
final class MonitorStatusItems: NSObject {

    /// 菜单栏项目宽度固定。内容收紧会让 item 反复变宽变窄，
    /// 把左侧所有菜单栏图标一起推来推去；这里按最长可能文本预留，
    /// 只多留 100% / 999M 这类边界值需要的空间。
    static let networkWidth = width(for: ["↑ 999M", "↓ 999M"])
    static let cpuWidth = width(for: ["C 100%", "G 100%"])

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
    private let onSelect: (MonitorStatusKind, NSStatusBarButton) -> Void

    private var networkItem: NSStatusItem?
    private var cpuItem: NSStatusItem?
    private var networkAccessibility: String?
    private var cpuAccessibility: String?

    init(onSelect: @escaping (MonitorStatusKind, NSStatusBarButton) -> Void) {
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

    #if MACEXPERT_DEV_HOOKS
    var buttonForPreview: NSStatusBarButton? {
        networkItem?.button ?? cpuItem?.button
    }
    #endif

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
        let uploadText = Self.displayText(MonitorFormat.compactRate(upload))
        let downloadText = Self.displayText(MonitorFormat.compactRate(download))
        let cpuText = Self.displayText(MonitorFormat.percent(cpu))
        let gpuText = Self.displayText(MonitorFormat.percent(gpu))

        networkView.setTop(prefix: "↑", value: uploadText, color: .labelColor)
        networkView.setBottom(prefix: "↓", value: downloadText, color: .labelColor)
        setNetworkAccessibility(
            "网络：上传 \(uploadDetail)，下载 \(downloadDetail)（\(interfaceName)）"
        )

        cpuView.setTop(prefix: "C", value: cpuText, color: Self.usageColor(cpu))
        cpuView.setBottom(prefix: "G", value: gpuText, color: Self.usageColor(gpu))
        let gpuAccessibility = gpu == nil ? "GPU 不可用" : "GPU \(gpuText)"
        setCPUAccessibility("CPU \(cpuText)，\(gpuAccessibility)")
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

    /// 固定宽度下，异常长的文本会整段被裁掉、只剩前缀；宁可显示 `--`。
    private static func displayText(_ text: String) -> String {
        text.count <= 4 ? text : "--"
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
            view.widthAnchor.constraint(equalToConstant: length),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        return item
    }

    private func setNetworkAccessibility(_ text: String) {
        guard networkAccessibility != text else { return }
        networkAccessibility = text
        applyAccessibility(on: networkItem, text: text)
    }

    private func setCPUAccessibility(_ text: String) {
        guard cpuAccessibility != text else { return }
        cpuAccessibility = text
        applyAccessibility(on: cpuItem, text: text)
    }

    private func applyAccessibility(on item: NSStatusItem?, text: String) {
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
        networkAccessibility = nil
    }

    private func removeCPUItem() {
        guard let cpuItem else { return }
        NSStatusBar.system.removeStatusItem(cpuItem)
        cpuView.removeFromSuperview()
        self.cpuItem = nil
        cpuAccessibility = nil
    }

    @objc private func clicked(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton else { return }
        let kind: MonitorStatusKind = (networkItem?.button === button) ? .network : .processor
        onSelect(kind, button)
    }
}

// MARK: - 双行视图

/// 菜单栏 item 里的两行文字。
/// 直接绘制而不是叠 `NSTextField`：状态栏每次刷新都会做一次离屏快照，
/// 子视图和 Auto Layout 会让快照成本高出一个数量级。
/// 点击必须穿透到 status item 的 button，所以 `hitTest` 固定返回 nil。
final class MonitorTwoLineStatusView: NSView {

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

    private let leadingInset: CGFloat
    private var topLine = NSAttributedString(string: "")
    private var bottomLine = NSAttributedString(string: "")
    private var lastTop: LineSignature?
    private var lastBottom: LineSignature?

    private struct LineSignature: Equatable {
        let prefix: String
        let value: String
        let color: NSColor

        static func == (lhs: LineSignature, rhs: LineSignature) -> Bool {
            lhs.prefix == rhs.prefix
                && lhs.value == rhs.value
                && lhs.color.isEqual(rhs.color)
        }
    }

    init(leadingInset: CGFloat) {
        self.leadingInset = leadingInset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 翻转坐标系，让文字从行框顶部向下排，和原有标签的视觉效果一致。
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// 首次布局时视图可能先以很窄的宽度画过一次；宽度恢复后如果不重绘，
    /// 图层会一直保留“只有箭头、没有数值”的旧内容。尺寸变化必须重新绘制。
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        topLine.draw(in: lineRect(top: true))
        bottomLine.draw(in: lineRect(top: false))
    }

    func setTop(prefix: String, value: String, color: NSColor) {
        let signature = LineSignature(prefix: prefix, value: value, color: color)
        guard signature != lastTop else { return }
        lastTop = signature
        topLine = makeLine(prefix: prefix, value: value, color: color)
        needsDisplay = true
    }

    func setBottom(prefix: String, value: String, color: NSColor) {
        let signature = LineSignature(prefix: prefix, value: value, color: color)
        guard signature != lastBottom else { return }
        lastBottom = signature
        bottomLine = makeLine(prefix: prefix, value: value, color: color)
        needsDisplay = true
    }

    /// 两行文字按 10pt 行距居中，比均分按钮高度更紧凑。
    private func lineRect(top: Bool) -> NSRect {
        let lineHeight = min(11, bounds.height)
        let pitch = max(0, lineHeight - 1)
        let width = max(0, bounds.width - leadingInset - 2)
        let offset = top ? -pitch / 2 : pitch / 2
        return NSRect(
            x: leadingInset,
            y: bounds.midY + offset - lineHeight / 2,
            width: width,
            height: lineHeight
        )
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
}

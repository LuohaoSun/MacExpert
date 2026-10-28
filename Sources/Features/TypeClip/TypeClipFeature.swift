import AppKit
import Carbon
import Combine

// MARK: - 输入法处理策略

/// `restoreIME` 只在 `autoIME` 打开时才有意义，所以合并成三态，
/// 避免出现「不切英文却要求恢复」的无意义组合。
enum IMEMode: String, CaseIterable, Identifiable, Hashable {
    case off
    case englishOnly
    case englishAndRestore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "不动"
        case .englishOnly: return "切英文"
        case .englishAndRestore: return "切并恢复"
        }
    }

    var detail: String {
        switch self {
        case .off: return "保持当前输入法敲入"
        case .englishOnly: return "触发时切英文，结束后保持英文"
        case .englishAndRestore: return "触发时切英文，结束后切回原输入法"
        }
    }

    var autoIME: Bool { self != .off }
    var restoreIME: Bool { self == .englishAndRestore }
}

// MARK: - TypeClip 功能状态

final class TypeClipFeature: ObservableObject {
    static let shared = TypeClipFeature()

    enum Phase {
        case idle, typing, done, aborted, failed
    }

    let engine = TyperEngine()
    private let defaults = UserDefaults.standard
    private var lastPasteboardChangeCount = -1

    @Published var status = "就绪"
    @Published var lastError: String?
    @Published var clipboardSummary = "正在读取剪贴板…"
    @Published var clipboardOK = false
    @Published var progress: Double?

    /// 总开关。关闭后全局热键与菜单动作都不再触发敲入，飞行中的敲入会立即中断。
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "typeClipEnabled")
            syncHotkeys()
            if !enabled, engine.isActive { cancel() }
        }
    }

    /// 唯一的速度轴（ms/字符）。字符间隔、按住时长、随机抖动、修饰键延迟都由它派生。
    @Published var paceMs: Double {
        didSet {
            defaults.set(paceMs, forKey: "paceMs")
            if manual { manual = false }
        }
    }

    @Published var imeMode: IMEMode {
        didSet { defaults.set(imeMode.rawValue, forKey: "imeMode") }
    }

    /// 敲入结束后补一个 Return（与 ⌃⌘↩ 热键等价，方便只用 ⌃⌘V 的用户）。
    @Published var pressEnterSuffix: Bool {
        didSet { defaults.set(pressEnterSuffix, forKey: "pressEnterSuffix") }
    }

    /// 高级覆盖：直接指定四个原始参数，仅在速度轴与实测不符时用来排障。
    /// 改速度轴会自动退出覆盖，避免「滑块看着是 100 实际发的是 250」这种分裂状态。
    @Published var manual: Bool {
        didSet {
            defaults.set(manual, forKey: "manual")
            if manual { seedRawFromPace() }
        }
    }

    @Published var intervalMs: Double {
        didSet { defaults.set(intervalMs, forKey: "intervalMs") }
    }
    @Published var holdMs: Double {
        didSet { defaults.set(holdMs, forKey: "holdMs") }
    }
    @Published var jitterMs: Double {
        didSet { defaults.set(jitterMs, forKey: "jitterMs") }
    }
    @Published var modifierDelayMs: Double {
        didSet { defaults.set(modifierDelayMs, forKey: "modifierDelayMs") }
    }

    /// 诊断日志：打开后日志里才记录逐字符注入路径与事件时刻表。
    /// 默认关——那两段含被敲入的字符本身（即剪贴板明文），平时没有记录的必要。
    @Published var debugLog: Bool {
        didSet { defaults.set(debugLog, forKey: "debugLog") }
    }

    // 纯 UI 状态，不落盘。
    @Published var advancedExpanded = false
    @Published var diagnosticsExpanded = false
    @Published var debugConfirmPending = false

    init() {
        // 迁移：老版本只有 intervalMs 一个数，它就是速度轴。
        let pace = defaults.object(forKey: "paceMs") as? Double
            ?? defaults.object(forKey: "intervalMs") as? Double ?? 100
        let mode: IMEMode
        if let raw = defaults.string(forKey: "imeMode"), let saved = IMEMode(rawValue: raw) {
            mode = saved
        } else {
            let auto = defaults.object(forKey: "autoIME") as? Bool ?? true
            let restore = defaults.object(forKey: "restoreIME") as? Bool ?? false
            mode = auto ? (restore ? .englishAndRestore : .englishOnly) : .off
        }

        enabled = defaults.object(forKey: "typeClipEnabled") as? Bool ?? true
        paceMs = pace
        imeMode = mode
        pressEnterSuffix = defaults.bool(forKey: "pressEnterSuffix")
        manual = defaults.bool(forKey: "manual")
        debugLog = defaults.bool(forKey: "debugLog")

        let d = Self.derived(paceMs: pace)
        intervalMs = defaults.object(forKey: "intervalMs") as? Double ?? d.interval
        holdMs = defaults.object(forKey: "holdMs") as? Double ?? d.hold
        jitterMs = defaults.object(forKey: "jitterMs") as? Double ?? d.jitter
        modifierDelayMs = defaults.object(forKey: "modifierDelayMs") as? Double ?? d.modifierDelay

        // 属性观察器在 init 里不会触发，所以这里显式落盘。
        defaults.set(pace, forKey: "paceMs")
        defaults.set(mode.rawValue, forKey: "imeMode")

        engine.onProgress = { [weak self] typed, total in
            guard let self else { return }
            self.status = "敲入中 \(typed)/\(total)"
            self.progress = Double(typed) / Double(max(total, 1))
            self.lastError = nil
        }
        engine.onFinish = { [weak self] in
            self?.status = "完成 ✓"
            self?.progress = nil
        }
    }

    // MARK: 派生值

    /// 速度轴 → 四个引擎参数。hold 必须短于 interval（否则按键会叠住），
    /// modifierDelay 保底 100ms——实测 50ms 时堡垒机远程端会来不及登记 shift，# 退化成裸 3。
    static func derived(paceMs: Double) -> (interval: Double, hold: Double, jitter: Double, modifierDelay: Double) {
        (interval: paceMs,
         hold: min(max(0.6 * paceMs, 15), 150),
         jitter: 0.3 * paceMs,
         modifierDelay: max(paceMs, 100))
    }

    var effectiveRaw: (interval: Double, hold: Double, jitter: Double, modifierDelay: Double) {
        let d = Self.derived(paceMs: paceMs)
        return manual ? (intervalMs, holdMs, jitterMs, modifierDelayMs) : d
    }

    var derivedDetail: String {
        let d = Self.derived(paceMs: paceMs)
        return "按住 \(Int(d.hold))ms · 抖动 \(Int(d.jitter))ms · 修饰键 \(Int(d.modifierDelay))ms"
    }

    var engineConfig: TyperEngine.Config {
        let p = effectiveRaw
        return .init(
            interval: p.interval / 1000,
            hold: p.hold / 1000,
            jitter: p.jitter / 1000,
            lead: 0.5,
            autoIME: imeMode.autoIME,
            restoreIME: imeMode.restoreIME,
            modifierDelay: p.modifierDelay / 1000,
            debugLog: debugLog
        )
    }

    // MARK: 状态摘要

    var isActive: Bool { engine.isActive }

    var phase: Phase {
        if engine.isActive { return .typing }
        if lastError != nil { return .failed }
        if status.hasPrefix("完成") { return .done }
        if status.hasPrefix("已中断") { return .aborted }
        return .idle
    }

    var statusLine: String? {
        if let lastError { return lastError }
        return status == "就绪" ? nil : status
    }

    /// 打开高级覆盖时，用当前派生值填满四个原始参数作为起点。
    private func seedRawFromPace() {
        let d = Self.derived(paceMs: paceMs)
        intervalMs = d.interval
        holdMs = d.hold
        jitterMs = d.jitter
        modifierDelayMs = d.modifierDelay
    }

    // MARK: 触发入口

    func handleHotkey(enter: Bool = false) {
        guard enabled else { return }

        // 热键是全局的：把主窗口切回「敲入」页，进度和错误才有地方显示。
        // 走 open() 会触发模块的 onOpened()，剪贴板刷新只做一次。
        AppState.shared.open(.feature(.typeClip))

        if engine.isActive {
            cancel()
            return
        }

        guard AXIsProcessTrusted() else {
            AppState.shared.markUntrusted()
            lastError = "缺少辅助功能权限，无法模拟键盘"
            Permissions.requestAccess()
            return
        }

        // 密码框等安全输入场景下系统会丢弃模拟按键，直接拦下来别让用户白等。
        guard !IsSecureEventInputEnabled() else {
            fail("当前应用处于安全输入状态（密码框），已阻止敲入")
            return
        }

        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string) else {
            let kinds = (pb.types ?? []).map(\.rawValue)
            let isImage = kinds.contains {
                $0.contains("tiff") || $0.contains("png") || $0.contains("jpeg") || $0.contains("heic")
            }
            fail(isImage ? "剪贴板是图像，无法敲入" : "剪贴板没有文本（可能是文件/图像）")
            return
        }

        let text = TyperEngine.clean(raw)
        guard !text.isEmpty else {
            fail("剪贴板文本为空（或只有换行/空白）")
            return
        }

        let withEnter = enter || pressEnterSuffix
        progress = 0
        let duration = engine.start(text: text, pressEnter: withEnter, cfg: engineConfig)
        status = "开始敲入 \(text.count) 字符 · 约 \(Int(duration))s" + (withEnter ? " · 结尾回车" : "")
        lastError = nil
    }

    func cancel() {
        engine.cancel()
        progress = nil
        status = "已中断 ⏹"
    }

    private func fail(_ message: String) {
        NSSound.beep()
        status = "未敲入"
        lastError = message
        progress = nil
    }

    // MARK: 剪贴板摘要

    /// 剪贴板状态摘要与可敲入性检查（边界情况：图像/文件/空文本/超长）。
    func refreshPasteboard(force: Bool = false) {
        let pb = NSPasteboard.general
        if !force, pb.changeCount == lastPasteboardChangeCount { return }
        lastPasteboardChangeCount = pb.changeCount
        let kinds = (pb.types ?? []).map(\.rawValue)

        if let raw = pb.string(forType: .string) {
            let cleaned = TyperEngine.clean(raw)
            if cleaned.isEmpty {
                clipboardSummary = "剪贴板是空白文本（仅换行/空白），无法敲入"
                clipboardOK = false
            } else {
                let preview = cleaned.prefix(90)
                    .replacingOccurrences(of: "\n", with: "⏎")
                    .replacingOccurrences(of: "\t", with: "⇥")
                let suffix = cleaned.count > 90 ? "… · \(cleaned.count) 字符" : " · \(cleaned.count) 字符"
                clipboardSummary = "\(preview)\(suffix)"
                clipboardOK = true
            }
        } else if kinds.contains(where: {
            $0.contains("tiff") || $0.contains("png") || $0.contains("jpeg") || $0.contains("heic")
        }) {
            clipboardSummary = "剪贴板是图像，无法敲入"
            clipboardOK = false
        } else if pb.data(forType: .fileURL) != nil || kinds.contains(where: { $0.contains("file") }) {
            clipboardSummary = "剪贴板是文件/其他非文本内容，无法敲入"
            clipboardOK = false
        } else {
            clipboardSummary = "剪贴板没有可敲入的文本"
            clipboardOK = false
        }
    }
}

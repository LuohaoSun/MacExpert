import AppKit
import Combine
import Foundation

// MARK: - 鼠标按键映射功能

final class KeyMappingFeature: ObservableObject {

    static let shared = KeyMappingFeature()

    struct LastTrigger: Equatable {
        let button: Int
        let combo: KeyCombo
        let app: String
        let date: Date
    }

    struct DetectedEvent: Identifiable, Equatable {
        let id = UUID()
        let button: Int
        let app: String
        let date: Date
        let mapped: Bool
    }

    private struct PendingTrigger {
        let combo: KeyCombo
        let app: String
    }

    private let store: KeyMappingStore
    private let tap = MouseButtonTap()
    private let sender = ShortcutSender()
    private var wakeObserver: NSObjectProtocol?
    private var installed = false
    private var captureActive = false
    private var isPreview = false
    private var pendingTriggers: [Int: PendingTrigger] = [:]

    @Published private(set) var mappings: [KeyMapping] {
        didSet {
            guard !isPreview else { return }
            _ = store.saveMappings(mappings)
        }
    }

    @Published var enabled: Bool {
        didSet {
            guard !isPreview else { return }
            store.setEnabled(enabled)
            updateTap()
        }
    }

    @Published var sendDelayMs: Double {
        didSet {
            guard !isPreview else { return }
            store.setSendDelayMs(sendDelayMs)
        }
    }

    @Published private(set) var tapState: MouseButtonTap.State = .stopped
    @Published private(set) var lastTrigger: LastTrigger?
    @Published private(set) var lastDetected: DetectedEvent?
    @Published private(set) var recentEvents: [DetectedEvent] = []

    // 页面与弹窗的临时状态，不落盘。
    @Published var editorContext: KeyMappingEditorContext?
    @Published var pendingDelete: KeyMapping?
    @Published var advancedExpanded = false

    private init(store: KeyMappingStore = KeyMappingStore()) {
        self.store = store
        self.mappings = store.loadMappings()
        self.enabled = store.isEnabled
        self.sendDelayMs = store.sendDelayMs
    }

    // MARK: - 生命周期

    func start() {
        guard !installed else { return }
        installed = true

        tap.onButtonDown = { [weak self] button in
            self?.handleButtonDown(button) ?? false
        }
        tap.onButtonUp = { [weak self] button in
            self?.handleButtonUp(button)
        }
        tap.onEvent = { [weak self] button in
            self?.recordDetected(button)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartAfterWake()
        }

        updateTap()
    }

    func shutdown() {
        captureActive = false
        pendingTriggers.removeAll()
        tap.captureHandler = nil
        tap.stop()
        tapState = .stopped
        sender.releaseAll()

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// App 激活、页面打开或授权状态变化时调用。
    func refreshPermission() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        guard AXIsProcessTrusted() else {
            captureActive = false
            pendingTriggers.removeAll()
            tap.captureHandler = nil
            if tap.state == .running {
                tap.stop()
            }
            tapState = .permissionDenied
            return
        }
        updateTap()
    }

    func restartTap() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        pendingTriggers.removeAll()
        tap.stop()
        tapState = .stopped
        updateTap()
    }

    // MARK: - 计算属性

    var activeCount: Int {
        mappings.reduce(0) { $0 + ($1.enabled ? 1 : 0) }
    }

    var hasActiveMappings: Bool {
        mappings.contains { $0.enabled }
    }

    // MARK: - 编辑弹窗

    func openEditor(mapping: KeyMapping? = nil, preset: KeyMapping? = nil) {
        pendingTriggers.removeAll()
        let draft: KeyMappingDraft

        if let mapping {
            draft = KeyMappingDraft(
                id: mapping.id,
                button: mapping.button,
                combo: mapping.combo,
                name: mapping.name,
                enabled: mapping.enabled,
                isNew: false
            )
        } else if let preset {
            draft = KeyMappingDraft(
                id: UUID(),
                button: preset.button,
                combo: preset.combo,
                name: preset.name,
                enabled: true,
                isNew: true
            )
        } else {
            draft = KeyMappingDraft(
                id: UUID(),
                button: firstAvailableButton(),
                combo: nil,
                name: "",
                enabled: true,
                isNew: true
            )
        }

        let model = KeyMappingEditorModel(draft: draft, feature: self)
        editorContext = KeyMappingEditorContext(id: draft.id, model: model)
    }

    func closeEditor() {
        editorContext?.model.cancel()
        editorContext = nil
    }

    func finishEditor(context: KeyMappingEditorContext, mapping: KeyMapping) {
        if context.model.isNew {
            add(mapping)
        } else {
            update(mapping)
        }
        editorContext = nil
    }

    func firstAvailableButton() -> Int {
        for button in [3, 4, 5, 2] where !mappings.contains(where: { $0.button == button }) {
            return button
        }
        return 3
    }

    // MARK: - 增删改

    func add(_ mapping: KeyMapping) {
        mappings.append(mapping)
        updateTap()
    }

    func update(_ mapping: KeyMapping) {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index] = mapping
        updateTap()
    }

    func delete(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        if pendingDelete?.id == id {
            pendingDelete = nil
        }
        updateTap()
    }

    func setEnabled(id: UUID, _ value: Bool) {
        guard let index = mappings.firstIndex(where: { $0.id == id }) else { return }
        mappings[index].enabled = value
        updateTap()
    }

    // MARK: - 鼠标键捕获

    @discardableResult
    func beginCapture(_ completion: @escaping (Int) -> Void) -> Bool {
        guard enabled,
              editorContext != nil,
              !isPreview,
              !RuntimeFlags.isRenderingPreview else {
            return false
        }

        captureActive = true
        pendingTriggers.removeAll()
        updateTap()

        guard tap.state == .running else {
            captureActive = false
            updateTap()
            return false
        }

        tap.captureHandler = { [weak self] button in
            guard let self else { return }
            self.captureActive = false
            // 不要在事件 tap 回调里直接 stop/invalidate，延迟到下一轮 RunLoop。
            DispatchQueue.main.async { self.updateTap() }
            completion(button)
        }
        return true
    }

    func cancelCapture() {
        tap.captureHandler = nil
        captureActive = false
        updateTap()
    }

    // MARK: - 事件

    private func handleButtonDown(_ button: Int) -> Bool {
        // 编辑弹窗打开时暂停映射，避免录制快捷键时侧键误触发；
        // 此时鼠标键捕获由 tap.captureHandler 优先处理。
        guard editorContext == nil else {
            pendingTriggers.removeValue(forKey: button)
            return false
        }

        let resolver = MappingResolver(enabled: enabled, mappings: mappings)
        guard let mapping = resolver.mapping(for: button) else {
            pendingTriggers.removeValue(forKey: button)
            return false
        }

        // 先记下这次点击，等鼠标抬起后再发快捷键。
        // 按下时立刻发会和鼠标事件抢顺序，部分应用/系统快捷键会直接丢掉。
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "当前应用"
        pendingTriggers[button] = PendingTrigger(combo: mapping.combo, app: app)
        return true
    }

    private func handleButtonUp(_ button: Int) {
        guard let pending = pendingTriggers.removeValue(forKey: button) else { return }
        // 按住侧键期间映射可能被关掉或删掉，抬起时再确认一次。
        guard enabled, mappings.contains(where: { $0.enabled && $0.button == button }) else { return }

        sender.send(pending.combo, delayMs: sendDelayMs)
        lastTrigger = LastTrigger(
            button: button,
            combo: pending.combo,
            app: pending.app,
            date: Date()
        )
    }

    private func recordDetected(_ button: Int) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "当前应用"
        let mapped = editorContext == nil
            && enabled
            && mappings.contains { $0.enabled && $0.button == button }
        let event = DetectedEvent(button: button, app: app, date: Date(), mapped: mapped)

        lastDetected = event
        recentEvents.append(event)
        if recentEvents.count > 20 {
            recentEvents.removeFirst(recentEvents.count - 20)
        }
    }

    private func updateTap() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }

        let shouldRun = enabled && (captureActive || hasActiveMappings)

        if shouldRun {
            if tap.state != .running {
                _ = tap.start()
            }
            tapState = tap.state
        } else {
            pendingTriggers.removeAll()
            if tap.state != .stopped {
                tap.stop()
            }
            tapState = tap.state
        }
    }

    private func restartAfterWake() {
        guard !isPreview, !RuntimeFlags.isRenderingPreview else { return }
        guard enabled, captureActive || hasActiveMappings else { return }
        tap.stop()
        tapState = .stopped
        updateTap()
    }
}

// MARK: - 预览数据

#if MACEXPERT_DEV_HOOKS
extension KeyMappingFeature {
    func applyPreviewData() {
        isPreview = true
        enabled = true
        mappings = [
            KeyMapping(
                id: UUID(),
                button: 3,
                combo: KeyMappingPresets.copy,
                name: "复制",
                enabled: true
            ),
            KeyMapping(
                id: UUID(),
                button: 4,
                combo: KeyMappingPresets.paste,
                name: "粘贴",
                enabled: true
            ),
            KeyMapping(
                id: UUID(),
                button: 2,
                combo: KeyMappingPresets.typeClip,
                name: "敲入剪贴板",
                enabled: true
            ),
        ]

        let event = DetectedEvent(button: 3, app: "Safari", date: Date(), mapped: true)
        lastDetected = event
        recentEvents = [event]
        lastTrigger = LastTrigger(
            button: 3,
            combo: KeyMappingPresets.copy,
            app: "Safari",
            date: Date()
        )
        tapState = .running
    }

    /// 预览空状态：不写盘，只改内存。
    func applyEmptyPreviewData() {
        isPreview = true
        enabled = true
        mappings = []
        lastDetected = nil
        recentEvents = []
        lastTrigger = nil
        tapState = .stopped
    }
}
#endif

import AppKit
import Combine
import Foundation

// MARK: - 编辑弹窗上下文

struct KeyMappingEditorContext: Identifiable {
    let id: UUID
    let model: KeyMappingEditorModel
}

// MARK: - 编辑状态

/// 编辑弹窗的草稿、校验、鼠标键捕获和快捷键录制。
/// 不直接保存配置，保存动作由 `KeyMappingFeature` 统一处理。
final class KeyMappingEditorModel: ObservableObject {

    let id: UUID
    let isNew: Bool
    let enabled: Bool
    let feature: KeyMappingFeature

    @Published var button: Int {
        didSet { captureError = nil }
    }
    @Published var combo: KeyCombo?
    @Published var name: String {
        didSet {
            guard !applyingSuggestion else { return }
            nameEdited = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    @Published var isCapturingButton = false
    @Published var isRecordingShortcut = false
    @Published var captureError: String?
    @Published var showDeleteConfirm = false

    private(set) var nameEdited: Bool
    private var applyingSuggestion = false
    private var recorder: ShortcutRecorder?

    init(draft: KeyMappingDraft, feature: KeyMappingFeature) {
        self.id = draft.id
        self.isNew = draft.isNew
        self.enabled = draft.enabled
        self.feature = feature
        self.button = draft.button
        self.combo = draft.combo
        self.nameEdited = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.name = draft.name

        if draft.name.isEmpty, !nameEdited, let combo = draft.combo {
            let suggestion = combo.suggestedName
            if !suggestion.isEmpty {
                self.name = suggestion
            }
        }
    }

    deinit {
        recorder?.stop()
    }

    var title: String {
        isNew ? "添加映射" : "编辑映射"
    }

    var errors: [String] {
        KeyMappingValidation.errors(
            combo: combo,
            button: button,
            mappings: feature.mappings,
            editingID: id
        )
    }

    var canSave: Bool {
        combo != nil && errors.isEmpty
    }

    var summaryName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (combo?.suggestedName ?? "") : trimmed
    }

    var buttonHint: String {
        MouseButton.hint(button)
    }

    func setCombo(_ combo: KeyCombo?) {
        self.combo = combo
        guard !nameEdited else { return }
        applyingSuggestion = true
        name = combo?.suggestedName ?? ""
        applyingSuggestion = false
    }

    // MARK: - 鼠标键捕获

    func toggleButtonCapture() {
        if isCapturingButton {
            stopButtonCapture()
            return
        }
        stopShortcutRecording()
        captureError = nil

        let started = feature.beginCapture { [weak self] button in
            guard let self else { return }
            self.isCapturingButton = false
            self.button = button
        }

        if started {
            isCapturingButton = true
        } else {
            captureError = "需要辅助功能权限和监听才能自动捕获；可以先手动选择按钮。"
        }
    }

    func stopButtonCapture() {
        feature.cancelCapture()
        isCapturingButton = false
    }

    // MARK: - 快捷键录制

    func toggleShortcutRecording() {
        if isRecordingShortcut {
            stopShortcutRecording()
            return
        }
        stopButtonCapture()
        captureError = nil

        let recorder = ShortcutRecorder()
        recorder.onCapture = { [weak self] combo in
            guard let self else { return }
            self.isRecordingShortcut = false
            self.setCombo(combo)
        }
        self.recorder = recorder
        recorder.start()
        isRecordingShortcut = true
    }

    func stopShortcutRecording() {
        recorder?.onCapture = nil
        recorder?.stop()
        recorder = nil
        isRecordingShortcut = false
    }

    // MARK: - 输出

    func buildMapping() -> KeyMapping? {
        guard let combo else { return nil }
        return KeyMapping(
            id: id,
            button: button,
            combo: combo,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: enabled
        )
    }

    func cancel() {
        stopButtonCapture()
        stopShortcutRecording()
    }
}

// MARK: - 快捷键录制器

/// 弹窗打开时抓取组合键，录制期间吞掉按键，避免边录边触发应用菜单快捷键。
///
/// 不用 `NSEvent.addLocalMonitorForEvents`：⌃← / ⌃→ 这类快捷键在到达应用之前
/// 就被系统拿去切换桌面了，本地监听根本看不到。录制时临时装一个只收 keyDown
/// 的 session 事件 tap，就能在系统处理前拿到原始按键；抓到后立刻拆除。
final class ShortcutRecorder {

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private var capturePending = false
    var onCapture: ((KeyCombo) -> Void)?

    var isRecording: Bool {
        tap != nil || monitor != nil || capturePending
    }

    func start() {
        guard tap == nil, monitor == nil, !capturePending else { return }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue

        // HID 层最靠前，能赶在系统切换桌面之前拿到 ⌃← / ⌃→；
        // 个别系统不允许建 HID tap 时退回 session 层，再不行退回本地监听。
        var created: CFMachPort?
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { continue }

            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                created = tap
                break
            }
            CFMachPortInvalidate(tap)
        }

        guard let tap = created else {
            // 没有辅助功能权限时 tap 建不起来，退回本地监听：普通键还能录，
            // 被系统抢先处理的组合键依旧录不到。
            startLocalMonitor()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            startLocalMonitor()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
    }

    private func startLocalMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.monitor != nil else { return event }
            if event.isARepeat { return nil }
            self.finish(with: event)
            return nil
        }
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        capturePending = false
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let recorder = Unmanaged<ShortcutRecorder>.fromOpaque(refcon).takeUnretainedValue()
        return recorder.handle(type, event: event)
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // 已经在收尾时继续吞掉剩余按键，避免组合键的第二个键漏给应用。
        guard !capturePending else { return nil }
        guard NSApp?.isActive == true else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
        guard let nsevent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }

        capturePending = true
        let combo = KeyCombo.from(event: nsevent)

        // 不在 tap 回调里直接拆除自己，交到下一轮主队列。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.stop()
            self.onCapture?(combo)
        }
        return nil
    }

    private func finish(with event: NSEvent) {
        guard !capturePending else { return }
        capturePending = true
        let combo = KeyCombo.from(event: event)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.stop()
            self.onCapture?(combo)
        }
    }

    deinit {
        stop()
    }
}

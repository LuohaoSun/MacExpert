import AppKit
import Carbon
import CoreGraphics
import Foundation

// MARK: - 修饰键

/// 映射里保存的修饰键。顺序固定为 ⌃⌥⇧⌘，展示和发送都按这个顺序。
enum Modifier: String, Codable, CaseIterable, Hashable {
    case control
    case option
    case shift
    case command

    var label: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .control: return CGKeyCode(kVK_Control)
        case .option: return CGKeyCode(kVK_Option)
        case .shift: return CGKeyCode(kVK_Shift)
        case .command: return CGKeyCode(kVK_Command)
        }
    }

    /// 修饰位 + 左侧设备位。事件形状与 TypeClip 的 flagsChanged 保持一致。
    var eventFlags: CGEventFlags {
        switch self {
        case .control: return [.maskControl, CGEventFlags(rawValue: 0x0001)]
        case .option: return [.maskAlternate, CGEventFlags(rawValue: 0x0020)]
        case .shift: return [.maskShift, CGEventFlags(rawValue: 0x0002)]
        case .command: return [.maskCommand, CGEventFlags(rawValue: 0x0008)]
        }
    }

    /// 固定展示顺序：⌃⌥⇧⌘。
    static let displayOrder: [Modifier] = [.control, .option, .shift, .command]

    static func from(_ flags: NSEvent.ModifierFlags) -> Set<Modifier> {
        var result: Set<Modifier> = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}

// MARK: - 键组合

/// 一个键盘组合。`keyCode` 是按下时的物理键，注入时按它重放；
/// `keyLabel` 只用于界面展示，录制时按当时布局生成。
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var keyLabel: String
    var modifiers: Set<Modifier>

    var orderedModifiers: [Modifier] {
        Modifier.displayOrder.filter { modifiers.contains($0) }
    }

    var displayCaps: [String] {
        orderedModifiers.map(\.label) + [keyLabel]
    }

    var displayText: String {
        displayCaps.joined()
    }

    /// 名称建议用的稳定键，例如 `command+shift+z`、`control+↑`。
    /// 顺序和展示顺序无关：修饰键按 ⌃⌥⌘⇧ 排列，方便查表。
    var lookupKey: String {
        let order: [Modifier] = [.control, .option, .command, .shift]
        let names = order.filter { modifiers.contains($0) }.map(\.rawValue)
        return (names + [keyLabel.lowercased()]).joined(separator: "+")
    }

    var suggestedName: String {
        KeyMappingNames.suggestion(for: self)
    }

    /// 真实键盘事件里，方向键、翻页键和 F 键自带 Function 位；
    /// 系统的 symbolic hotkey 也按这个位登记（⌃← / ⌃→ 的掩码是 0x840000）。
    /// 漏掉它时，合成的 ⌃← / ⌃→ 只会被当成普通方向键，切不了桌面。
    var needsFunctionFlag: Bool {
        Self.functionKeyCodes.contains(Int(keyCode))
    }

    /// F1–F12 的键码不连续（F1 是 122、F12 是 111），不能用范围匹配。
    private static let functionKeyCodes: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_ForwardDelete, kVK_Help,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    /// 字符事件的 flags：保留组合键修饰位，再按物理键补 Function 位。
    func keyEventFlags(base: CGEventFlags) -> CGEventFlags {
        needsFunctionFlag ? base.union(.maskSecondaryFn) : base
    }

    static func from(event: NSEvent) -> KeyCombo {
        KeyCombo(
            keyCode: event.keyCode,
            keyLabel: KeyLabel.label(for: event.keyCode, characters: event.charactersIgnoringModifiers),
            modifiers: Modifier.from(event.modifierFlags)
        )
    }
}

// MARK: - 键帽文案

enum KeyLabel {
    static func label(for keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_KeypadEnter: return "⌤"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let characters, let first = characters.first {
                let text = String(first)
                let scalars = text.unicodeScalars
                if scalars.count == 1,
                   let scalar = scalars.first,
                   scalar.value >= 32,
                   !(0xF700...0xF8FF).contains(scalar.value) {
                    return text.uppercased()
                }
            }
            return "键 \(keyCode)"
        }
    }
}

// MARK: - 持久化模型

struct KeyMapping: Codable, Identifiable, Equatable {
    var id: UUID
    var button: Int
    var combo: KeyCombo
    var name: String
    var enabled: Bool

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? combo.suggestedName : trimmed
    }
}

// MARK: - 鼠标按键

enum MouseButton {
    /// CGEvent 的 mouseEventButtonNumber：2 中键，3 起是侧键/额外键。
    static let supportedRange = 2...31

    static func isSupported(_ number: Int) -> Bool {
        supportedRange.contains(number)
    }

    static func label(_ number: Int) -> String {
        switch number {
        case 2: return "中键"
        case 3: return "侧键 1"
        case 4: return "侧键 2"
        case 5: return "侧键 3"
        default: return "按键 \(number)"
        }
    }

    static func hint(_ number: Int) -> String {
        switch number {
        case 2: return "系统按钮 2 · 中键，常被用于滚动或打开新标签页"
        case 3: return "系统按钮 3 · 多数鼠标的侧键 1（后退）"
        case 4: return "系统按钮 4 · 多数鼠标的侧键 2（前进）"
        case 5: return "系统按钮 5 · 额外的鼠标键"
        default: return "系统按钮 \(number) · 额外的鼠标键"
        }
    }
}

// MARK: - 常见名称

enum KeyMappingNames {
    static func suggestion(for combo: KeyCombo) -> String {
        suggestions[combo.lookupKey] ?? ""
    }

    private static let suggestions: [String: String] = [
        "command+c": "复制",
        "command+v": "粘贴",
        "command+x": "剪切",
        "command+z": "撤销",
        "command+shift+z": "重做",
        "command+[": "后退",
        "command+]": "前进",
        "control+command+v": "敲入剪贴板",
        "control+↑": "任务控制",
        "control+↓": "App Exposé",
        "control+←": "左切换桌面",
        "control+→": "右切换桌面",
        "command+tab": "切换应用",
        "command+␣": "聚焦搜索",
        "command+w": "关闭窗口",
        "command+t": "新标签页",
        "command+shift+t": "恢复标签页",
        "f11": "显示桌面",
    ]
}

// MARK: - 校验

enum KeyMappingValidation {
    /// 允许不带修饰键的安全键；普通字符键必须带修饰键，
    /// 否则侧键会让任何输入框里都冒出一个字母/符号。
    static let safeBareKeyCodes: Set<UInt16> = Set([
        UInt16(kVK_Return),
        UInt16(kVK_Tab),
        UInt16(kVK_Escape),
        UInt16(kVK_Space),
        UInt16(kVK_Delete),
        UInt16(kVK_ForwardDelete),
        UInt16(kVK_ANSI_KeypadEnter),
        UInt16(kVK_LeftArrow),
        UInt16(kVK_RightArrow),
        UInt16(kVK_UpArrow),
        UInt16(kVK_DownArrow),
        UInt16(kVK_Home),
        UInt16(kVK_End),
        UInt16(kVK_PageUp),
        UInt16(kVK_PageDown),
        UInt16(kVK_F1),
        UInt16(kVK_F2),
        UInt16(kVK_F3),
        UInt16(kVK_F4),
        UInt16(kVK_F5),
        UInt16(kVK_F6),
        UInt16(kVK_F7),
        UInt16(kVK_F8),
        UInt16(kVK_F9),
        UInt16(kVK_F10),
        UInt16(kVK_F11),
        UInt16(kVK_F12),
    ])

    static func errors(
        combo: KeyCombo?,
        button: Int,
        mappings: [KeyMapping],
        editingID: UUID?
    ) -> [String] {
        var errors: [String] = []

        if !MouseButton.isSupported(button) {
            errors.append("这个鼠标按键编号不受支持。")
        }

        if let combo,
           combo.modifiers.isEmpty,
           !safeBareKeyCodes.contains(combo.keyCode) {
            errors.append("不带修饰键的字符键会在所有输入框里输入字符，请加一个修饰键。")
        }

        if let existing = mappings.first(where: { $0.id != editingID && $0.button == button }) {
            let name = existing.displayName.isEmpty ? "未命名" : existing.displayName
            errors.append("\(MouseButton.label(button)) 已经映射给「\(name)」，请换一个鼠标键。")
        }

        return errors
    }
}

// MARK: - 预设

enum KeyMappingPresets {
    static let copy = KeyCombo(
        keyCode: UInt16(kVK_ANSI_C),
        keyLabel: "C",
        modifiers: [.command]
    )
    static let paste = KeyCombo(
        keyCode: UInt16(kVK_ANSI_V),
        keyLabel: "V",
        modifiers: [.command]
    )
    static let back = KeyCombo(
        keyCode: UInt16(kVK_ANSI_LeftBracket),
        keyLabel: "[",
        modifiers: [.command]
    )
    static let forward = KeyCombo(
        keyCode: UInt16(kVK_ANSI_RightBracket),
        keyLabel: "]",
        modifiers: [.command]
    )
    static let typeClip = KeyCombo(
        keyCode: UInt16(kVK_ANSI_V),
        keyLabel: "V",
        modifiers: [.control, .command]
    )
}

// MARK: - 编辑草稿

/// 编辑弹窗里的可空组合；保存时才转成 `KeyMapping`。
struct KeyMappingDraft {
    var id: UUID
    var button: Int
    var combo: KeyCombo?
    var name: String
    var enabled: Bool
    var isNew: Bool
}

// MARK: - 解析

struct MappingResolver {
    let enabled: Bool
    let mappings: [KeyMapping]

    func mapping(for button: Int) -> KeyMapping? {
        guard enabled else { return nil }
        return mappings.first { $0.enabled && $0.button == button }
    }
}

// MARK: - 存储

struct KeyMappingStore {
    static let mappingsKey = "keyMappings.v1"
    static let enabledKey = "keyMappingEnabled"
    static let sendDelayKey = "keyMappingSendDelayMs"
    static let defaultSendDelayMs: Double = 30

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMappings() -> [KeyMapping] {
        guard let data = defaults.data(forKey: Self.mappingsKey) else { return [] }
        do {
            return try JSONDecoder().decode([KeyMapping].self, from: data)
        } catch {
            NSLog("[MacExpert] 鼠标按键映射配置解码失败：%@", String(describing: error))
            return []
        }
    }

    @discardableResult
    func saveMappings(_ mappings: [KeyMapping]) -> Bool {
        do {
            let data = try JSONEncoder().encode(mappings)
            defaults.set(data, forKey: Self.mappingsKey)
            return true
        } catch {
            NSLog("[MacExpert] 鼠标按键映射配置保存失败：%@", String(describing: error))
            return false
        }
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
    }

    var sendDelayMs: Double {
        let value = defaults.object(forKey: Self.sendDelayKey) as? Double ?? Self.defaultSendDelayMs
        return min(max(value, 0), 200)
    }

    func setSendDelayMs(_ value: Double) {
        defaults.set(min(max(value, 0), 200), forKey: Self.sendDelayKey)
    }
}

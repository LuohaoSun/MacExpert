import AppKit
import Carbon
import Foundation

// MacExpert 的纯逻辑单元测试。
//
// 不用 XCTest（CLT 里没有 XCTest.framework），用最简单的 check 函数：
// 失败逐条打印，最后 exit(1)。这个文件不启动 NSApplication，不读剪贴板，
// 不注册热键，也不执行任何会发 CGEvent 的时间表。

private var checks = 0
private var failures = 0

private func check(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    checks += 1
    if !condition() {
        failures += 1
        print("❌ \(message)  [\(file):\(line)]")
    }
}

private func checkEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    checks += 1
    if actual != expected {
        failures += 1
        print("❌ \(message)：期望 \(expected)，实际 \(actual)  [\(file):\(line)]")
    }
}

private func checkClose(
    _ actual: Double,
    _ expected: Double,
    _ message: String,
    tolerance: Double = 1e-9,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    checks += 1
    if abs(actual - expected) > tolerance {
        failures += 1
        print("❌ \(message)：期望 \(expected)，实际 \(actual)  [\(file):\(line)]")
    }
}

// MARK: - TyperEngine.clean

private func testClean() {
    checkEqual(TyperEngine.clean("a\r\nb"), "a\nb", "\\r\\n 应折叠成 \\n")
    checkEqual(TyperEngine.clean("a\rb"), "ab", "单独的 \\r 应删除")
    checkEqual(TyperEngine.clean("a\tb"), "a\tb", "制表符 \\t 应保留")

    checkEqual(
        TyperEngine.clean("a\u{01}b\u{02}c\u{1F}d"),
        "abcd",
        "C0 控制字符应删除"
    )
    checkEqual(TyperEngine.clean("a\u{7F}b"), "ab", "DEL (0x7F) 应删除")
    checkEqual(TyperEngine.clean("a\u{F700}b"), "ab", "功能键私有区字符应删除")

    checkEqual(TyperEngine.clean("abc\n\n"), "abc", "结尾换行应全部删除")
    checkEqual(TyperEngine.clean("abc\r\n"), "abc", "结尾 \\r\\n 应全部删除")
    checkEqual(TyperEngine.clean("abc\n"), "abc", "单个结尾换行应删除")
    checkEqual(TyperEngine.clean("\n\n"), "", "只有换行时应清空")
    checkEqual(TyperEngine.clean("a\nb"), "a\nb", "中间换行应保留")

    // ZWJ 是组合 emoji 的粘合剂，绝不能当零宽字符删掉。
    let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
    checkEqual(TyperEngine.clean(family), family, "家庭 emoji 的 ZWJ 应原样保留")
    check(
        TyperEngine.clean(family).unicodeScalars.contains { $0.value == 0x200D },
        "清洗后仍应包含 U+200D (ZWJ)"
    )

    // ZWNJ 用于波斯语/印地语等正字法，也必须保留。
    let zwnj = "a\u{200C}b"
    checkEqual(TyperEngine.clean(zwnj), zwnj, "ZWNJ (U+200C) 应保留")

    checkEqual(
        TyperEngine.clean("a\u{200B}b\u{200E}c\u{200F}d\u{FEFF}e"),
        "abcde",
        "U+200B / U+200E / U+200F / U+FEFF 应删除"
    )

    let realistic = "第一行\r\n第二行\tTab\u{200B}结束\n"
    checkEqual(
        TyperEngine.clean(realistic),
        "第一行\n第二行\tTab结束",
        "混合输入应得到预期的清洗结果"
    )
}

// MARK: - TypeClipFeature.derived

private func testDerivedParameters() {
    // 取足够大的 pace，保证 hold 派生值仍小于 interval。
    let paces: [Double] = [25, 50, 100, 250, 1000]
    for pace in paces {
        let d = TypeClipFeature.derived(paceMs: pace)
        checkClose(d.interval, pace, "interval 应等于 pace (\(pace))")
        check(d.hold < d.interval, "pace \(pace)ms 时 hold (\(d.hold)) 应小于 interval")
        check(d.hold >= 15 && d.hold <= 150, "pace \(pace)ms 时 hold 应落在 [15,150]，实际 \(d.hold)")
        check(d.modifierDelay >= 100, "pace \(pace)ms 时 modifierDelay 应 ≥ 100，实际 \(d.modifierDelay)")
        checkClose(d.jitter, 0.3 * pace, "pace \(pace)ms 时 jitter 应为 0.3 × pace")
    }

    checkClose(TypeClipFeature.derived(paceMs: 10).hold, 15, "hold 下界应为 15ms")
    checkClose(TypeClipFeature.derived(paceMs: 1000).hold, 150, "hold 上界应为 150ms")
    checkClose(
        TypeClipFeature.derived(paceMs: 50).modifierDelay,
        100,
        "pace 低于 100ms 时 modifierDelay 应保底 100ms"
    )
    checkClose(
        TypeClipFeature.derived(paceMs: 500).modifierDelay,
        500,
        "pace 高于 100ms 时 modifierDelay 应跟随 pace"
    )
    checkClose(TypeClipFeature.derived(paceMs: 120).jitter, 36, "jitter 派生值")
}

// MARK: - Feature / MainSection

private func testFeatureRegistry() {
    checkEqual(
        Feature.allCases,
        [.typeClip, .keyMapping, .smoothScroll, .translate],
        "Feature.allCases 顺序与内容"
    )

    check(Feature.typeClip.isAvailable, "TypeClip 已注册模块，应可用")
    check(Feature.keyMapping.isAvailable, "鼠标按键映射已注册模块，应可用")
    check(Feature.smoothScroll.isAvailable, "平滑滚动已注册模块，应可用")
    check(Feature.translate.isAvailable, "热键翻译已注册模块，应可用")

    for feature in Feature.allCases {
        check(!feature.title.isEmpty, "\(feature.rawValue) 的标题不应为空")
        check(!feature.subtitle.isEmpty, "\(feature.rawValue) 的副标题不应为空")
        check(!feature.icon.isEmpty, "\(feature.rawValue) 的图标名不应为空")
        check(!feature.id.isEmpty, "\(feature.rawValue) 的 id 不应为空")
    }

    checkEqual(Feature.typeClip.title, "剪贴板敲入", "TypeClip 标题")
    checkEqual(Feature.keyMapping.title, "鼠标按键映射", "鼠标按键映射标题")
    checkEqual(Feature.smoothScroll.title, "平滑滚动", "平滑滚动标题")
    checkEqual(Feature.smoothScroll.subtitle, "鼠标滚轮 · 平滑与反向", "平滑滚动副标题")
    checkEqual(Feature.smoothScroll.icon, "scroll", "平滑滚动图标")
    checkEqual(Feature.translate.title, "热键翻译", "热键翻译标题")

    let typeClip = MainSection.feature(.typeClip)
    checkEqual(typeClip.id, "typeClip", "MainSection id 应使用 feature.rawValue")
    checkEqual(typeClip.title, Feature.typeClip.title, "MainSection 标题应转发 feature")
    checkEqual(typeClip.subtitle, Feature.typeClip.subtitle, "MainSection 副标题应转发 feature")
    checkEqual(typeClip.icon, Feature.typeClip.icon, "MainSection 图标应转发 feature")
    check(typeClip.badge == nil, "可用功能不应有「规划中」徽章")
    check(typeClip.isAvailable, "TypeClip 的 MainSection 应可用")

    let keyMapping = MainSection.feature(.keyMapping)
    check(keyMapping.badge == nil, "已注册功能不应显示「规划中」")
    check(keyMapping.isAvailable, "鼠标按键映射的 MainSection 应可用")

    let smoothScroll = MainSection.feature(.smoothScroll)
    check(smoothScroll.badge == nil, "平滑滚动不应显示「规划中」")
    check(smoothScroll.isAvailable, "平滑滚动的 MainSection 应可用")
    checkEqual(smoothScroll.id, "smoothScroll", "平滑滚动 MainSection id")
    let translate = MainSection.feature(.translate)
    check(translate.badge == nil, "热键翻译已注册，不应显示「规划中」")
    check(translate.isAvailable, "热键翻译的 MainSection 应可用")

    let settings = MainSection.settings
    checkEqual(settings.id, "settings", "设置页 id")
    checkEqual(settings.title, "设置", "设置页标题")
    check(!settings.title.isEmpty, "设置页标题不应为空")
    check(settings.isAvailable, "设置页始终可用")
    check(settings.badge == nil, "设置页没有徽章")
    checkEqual(settings.feature, nil, "设置页不属于任何 feature")
}

// MARK: - HotkeyFailure / HotkeyCenter 纯描述逻辑

private func testHotkeyDescriptions() {
    // HotkeyCenter.describe 是 private，只能验证 HotkeyFailure 作为值对象的行为，
    // 以及共享实例在未注册任何热键时是干净的。不要调用 installAll/register。
    let failure = HotkeyFailure(
        id: 1,
        name: "敲入剪贴板（⌃⌘V）",
        status: -9878,
        message: "快捷键已被其他应用占用"
    )

    checkEqual(failure.id, 1, "HotkeyFailure id")
    checkEqual(failure.name, "敲入剪贴板（⌃⌘V）", "HotkeyFailure name")
    checkEqual(failure.status, -9878, "HotkeyFailure status")
    check(!failure.message.isEmpty, "HotkeyFailure message 不应为空")
    checkEqual(failure.message, "快捷键已被其他应用占用", "HotkeyFailure message 内容")

    let same = HotkeyFailure(
        id: 1,
        name: "敲入剪贴板（⌃⌘V）",
        status: -9878,
        message: "快捷键已被其他应用占用"
    )
    checkEqual(failure, same, "HotkeyFailure 应可比较相等")
    checkEqual(Set([failure, same]).count, 1, "相同内容的 HotkeyFailure 应得到同一哈希")

    check(HotkeyCenter.shared.failures.isEmpty, "未注册热键时 failures 应为空")
    check(!HotkeyCenter.shared.failures.contains { $0.id == failure.id }, "共享实例不应包含测试值")
}

// MARK: - 鼠标按键映射

private func testKeyMapping() {
    let copy = KeyCombo(
        keyCode: UInt16(kVK_ANSI_C),
        keyLabel: "C",
        modifiers: [.command]
    )
    checkEqual(copy.displayCaps, ["⌘", "C"], "⌘C 键帽顺序")
    checkEqual(copy.displayText, "⌘C", "⌘C 展示文本")
    checkEqual(copy.suggestedName, "复制", "⌘C 名称建议")

    let redo = KeyCombo(
        keyCode: UInt16(kVK_ANSI_Z),
        keyLabel: "Z",
        modifiers: [.command, .shift]
    )
    checkEqual(redo.displayCaps, ["⇧", "⌘", "Z"], "⌘⇧Z 键帽顺序")
    checkEqual(redo.suggestedName, "重做", "⌘⇧Z 名称建议")

    let typeClip = KeyCombo(
        keyCode: UInt16(kVK_ANSI_V),
        keyLabel: "V",
        modifiers: [.control, .command]
    )
    checkEqual(typeClip.displayText, "⌃⌘V", "⌃⌘V 展示文本")
    checkEqual(typeClip.suggestedName, "敲入剪贴板", "⌃⌘V 名称建议")

    let allModifiers = KeyCombo(
        keyCode: UInt16(kVK_ANSI_V),
        keyLabel: "V",
        modifiers: [.control, .option, .shift, .command]
    )
    checkEqual(allModifiers.displayCaps, ["⌃", "⌥", "⇧", "⌘", "V"], "修饰键固定顺序")

    let back = KeyCombo(
        keyCode: UInt16(kVK_ANSI_LeftBracket),
        keyLabel: "[",
        modifiers: [.command]
    )
    checkEqual(back.displayText, "⌘[", "⌘[ 展示文本")
    checkEqual(back.suggestedName, "后退", "⌘[ 名称建议")

    checkEqual(Modifier.from([.command, .shift]), [.command, .shift], "修饰键解析")

    if let left = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.control],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{F702}",
        charactersIgnoringModifiers: "\u{F702}",
        isARepeat: false,
        keyCode: UInt16(kVK_LeftArrow)
    ) {
        let combo = KeyCombo.from(event: left)
        checkEqual(combo.modifiers, [.control], "⌃← 修饰键")
        checkEqual(combo.keyLabel, "←", "⌃← 键帽")
        checkEqual(combo.displayText, "⌃←", "⌃← 展示文本")
        checkEqual(combo.suggestedName, "左切换桌面", "⌃← 名称建议")
    } else {
        check(false, "无法构造 ⌃← 测试事件")
    }

    if let right = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.control],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{F703}",
        charactersIgnoringModifiers: "\u{F703}",
        isARepeat: false,
        keyCode: UInt16(kVK_RightArrow)
    ) {
        let combo = KeyCombo.from(event: right)
        checkEqual(combo.keyLabel, "→", "⌃→ 键帽")
        checkEqual(combo.suggestedName, "右切换桌面", "⌃→ 名称建议")
    } else {
        check(false, "无法构造 ⌃→ 测试事件")
    }

    checkEqual(KeyLabel.label(for: UInt16(kVK_Return), characters: nil), "↩", "回车键帽")
    checkEqual(KeyLabel.label(for: UInt16(kVK_LeftArrow), characters: nil), "←", "左方向键帽")
    checkEqual(KeyLabel.label(for: UInt16(kVK_F5), characters: nil), "F5", "F5 键帽")
    checkEqual(KeyLabel.label(for: UInt16(kVK_ANSI_C), characters: "c"), "C", "字母键帽")
    checkEqual(KeyLabel.label(for: UInt16(kVK_Space), characters: " "), "␣", "空格键帽")

    checkEqual(MouseButton.label(2), "中键", "按钮 2 名称")
    checkEqual(MouseButton.label(3), "侧键 1", "按钮 3 名称")
    checkEqual(MouseButton.label(4), "侧键 2", "按钮 4 名称")
    checkEqual(MouseButton.label(5), "侧键 3", "按钮 5 名称")
    checkEqual(MouseButton.label(6), "按键 6", "按钮 6 名称")
    check(MouseButton.isSupported(31), "按钮 31 应受支持")
    check(!MouseButton.isSupported(1), "按钮 1 不应受支持")

    let unnamed = KeyMapping(id: UUID(), button: 3, combo: copy, name: "", enabled: true)
    checkEqual(unnamed.displayName, "复制", "空名称应回退到组合名")
    let named = KeyMapping(id: UUID(), button: 3, combo: copy, name: "自定义", enabled: true)
    checkEqual(named.displayName, "自定义", "手填名称优先")

    check(
        KeyMappingValidation.errors(combo: copy, button: 3, mappings: [], editingID: nil).isEmpty,
        "⌘C 应通过校验"
    )
    let bareC = KeyCombo(keyCode: UInt16(kVK_ANSI_C), keyLabel: "C", modifiers: [])
    check(
        !KeyMappingValidation.errors(combo: bareC, button: 3, mappings: [], editingID: nil).isEmpty,
        "不带修饰键的字符键应被拒绝"
    )
    let bareReturn = KeyCombo(keyCode: UInt16(kVK_Return), keyLabel: "↩", modifiers: [])
    check(
        KeyMappingValidation.errors(combo: bareReturn, button: 3, mappings: [], editingID: nil).isEmpty,
        "不带修饰键的回车应允许"
    )
    check(
        !KeyMappingValidation.errors(combo: copy, button: 1, mappings: [], editingID: nil).isEmpty,
        "按钮 1 应被拒绝"
    )

    let existing = KeyMapping(id: UUID(), button: 3, combo: back, name: "后退", enabled: true)
    check(
        !KeyMappingValidation.errors(combo: copy, button: 3, mappings: [existing], editingID: UUID()).isEmpty,
        "重复按钮应被拒绝"
    )
    check(
        KeyMappingValidation.errors(combo: copy, button: 3, mappings: [existing], editingID: existing.id).isEmpty,
        "编辑自己不应算重复"
    )

    var tracker = ButtonPressTracker()
    check(tracker.down(3, consume: true), "命中映射时 down 应吞掉")
    check(tracker.dragged(3), "吞掉 down 后 drag 应继续吞")
    check(tracker.up(3), "吞掉 down 后 up 应吞")
    check(!tracker.dragged(3), "抬起后 drag 不再吞")
    check(!tracker.down(4, consume: false), "未命中不吞")
    check(!tracker.up(4), "未命中的 up 不吞")

    let enabledMapping = KeyMapping(id: UUID(), button: 3, combo: copy, name: "复制", enabled: true)
    let disabledMapping = KeyMapping(id: UUID(), button: 4, combo: copy, name: "复制", enabled: false)
    let resolver = MappingResolver(enabled: true, mappings: [enabledMapping, disabledMapping])
    check(resolver.mapping(for: 3)?.id == enabledMapping.id, "应命中启用的映射")
    check(resolver.mapping(for: 4) == nil, "不应命中停用的映射")
    check(
        MappingResolver(enabled: false, mappings: [enabledMapping]).mapping(for: 3) == nil,
        "总开关关闭时不应命中"
    )

    let suite = "com.slh.macexpert.tests.keymapping"
    if let defaults = UserDefaults(suiteName: suite) {
        defaults.removePersistentDomain(forName: suite)
        let store = KeyMappingStore(defaults: defaults)
        check(store.loadMappings().isEmpty, "新存储应为空")
        check(store.isEnabled, "默认应启用")
        checkClose(store.sendDelayMs, 30, "默认发送间隔 30ms")

        let saved = [
            enabledMapping,
            KeyMapping(id: UUID(), button: 4, combo: redo, name: "重做", enabled: false),
        ]
        check(store.saveMappings(saved), "保存映射应成功")
        checkEqual(store.loadMappings(), saved, "映射应能往返")
        store.setEnabled(false)
        check(!store.isEnabled, "总开关应能持久化")
        store.setSendDelayMs(500)
        checkClose(store.sendDelayMs, 200, "发送间隔上限应夹到 200")
        store.setSendDelayMs(-10)
        checkClose(store.sendDelayMs, 0, "发送间隔下限应夹到 0")
        defaults.removePersistentDomain(forName: suite)
    } else {
        check(false, "无法创建测试 UserDefaults suite")
    }
}

// MARK: - 平滑滚动：分类与方向

private func testSmoothScrollClassification() {
    let wheel = ScrollSample(
        dxPoints: 0,
        dyPoints: 10,
        lineDeltaX: 0,
        lineDeltaY: 1,
        flags: [],
        targetPID: 100
    )
    checkEqual(wheel.disposition, .takeOver, "普通滚轮事件应接管")
    checkEqual(wheel.scrollDY, ScrollSample.minimumWheelStep, "小步长应归一化到最小滚动距离")

    // 点增量和行数一样小（经典滚轮）时按行换算，再归一化到最小步长。
    let lineWheel = ScrollSample(dxPoints: 0, dyPoints: 1, lineDeltaY: 1)
    checkEqual(lineWheel.scrollDY, ScrollSample.minimumWheelStep, "经典滚轮一格应达到最小滚动距离")

    // 大于最小步长的输入保持原样；连续事件不归一化，保留高分辨率细粒度。
    checkEqual(ScrollSample(dyPoints: 50, lineDeltaY: 5).scrollDY, 50, "较大步长不应被归一化")
    checkEqual(ScrollSample(dyPoints: 5, isContinuous: true).scrollDY, 5, "连续事件不做最小步长归一化")

    let trackpad = ScrollSample(
        dxPoints: 2,
        dyPoints: 12,
        isContinuous: true,
        phase: ScrollPhase.changed.rawValue
    )
    checkEqual(trackpad.disposition, .passThrough(.trackpadLike), "带 phase 的事件应放行")

    let momentum = ScrollSample(
        dyPoints: 8,
        isContinuous: true,
        momentumPhase: ScrollPhase.changed.rawValue
    )
    checkEqual(momentum.disposition, .passThrough(.trackpadLike), "带 momentumPhase 的事件应放行")

    let zoom = ScrollSample(
        dyPoints: 10,
        lineDeltaY: 1,
        flags: [.maskCommand]
    )
    checkEqual(zoom.disposition, .passThrough(.command), "⌘+滚轮是缩放，应放行")

    let own = ScrollSample(
        dyPoints: 10,
        lineDeltaY: 1,
        sourceUserData: ScrollMarker.value
    )
    checkEqual(own.disposition, .passThrough(.ownEvent), "自己合成的事件应放行，防自激")

    let empty = ScrollSample()
    checkEqual(empty.disposition, .passThrough(.noDelta), "没有增量的事件应放行")

    // 平滑关闭：只在原事件上改字段，接着原样放行，不吞事件。
    checkEqual(
        wheel.plan(smooth: false, reverseVertical: false, reverseHorizontal: false),
        .modifyAndPass(vertical: false, horizontal: false),
        "平滑关闭时不应吞事件，也不应进引擎"
    )
    checkEqual(
        wheel.plan(smooth: true, reverseVertical: false, reverseHorizontal: false),
        .swallowAndSmooth(dx: 0, dy: ScrollSample.minimumWheelStep),
        "平滑开启时应把增量交给引擎"
    )
    checkEqual(
        trackpad.plan(smooth: true, reverseVertical: true, reverseHorizontal: true),
        .passThrough(.trackpadLike),
        "放行的事件即使开了反向也应原样返回"
    )
}

private func testSmoothScrollReverse() {
    let sample = ScrollSample(
        dxPoints: 4,
        dyPoints: 10,
        fixedDX: 4.5,
        fixedDY: 10.5,
        lineDeltaX: 2,
        lineDeltaY: 1
    )

    let vertical = sample.reversed(vertical: true, horizontal: false)
    checkEqual(vertical.dyPoints, -10, "垂直反向应翻转点增量")
    checkEqual(vertical.fixedDY, -10.5, "垂直反向应翻转固定点增量")
    checkEqual(vertical.lineDeltaY, -1, "垂直反向应翻转行增量")
    checkEqual(vertical.dxPoints, 4, "垂直反向不应动水平点增量")
    checkEqual(vertical.fixedDX, 4.5, "垂直反向不应动水平固定点增量")
    checkEqual(vertical.lineDeltaX, 2, "垂直反向不应动水平行增量")

    let horizontal = sample.reversed(vertical: false, horizontal: true)
    checkEqual(horizontal.dxPoints, -4, "水平反向应翻转点增量")
    checkEqual(horizontal.fixedDX, -4.5, "水平反向应翻转固定点增量")
    checkEqual(horizontal.lineDeltaX, -2, "水平反向应翻转行增量")
    checkEqual(horizontal.dyPoints, 10, "水平反向不应动垂直点增量")

    let both = sample.reversed(vertical: true, horizontal: true)
    checkEqual(both.dyPoints, -10, "双轴反向的垂直增量")
    checkEqual(both.dxPoints, -4, "双轴反向的水平增量")

    checkEqual(
        sample.plan(smooth: true, reverseVertical: true, reverseHorizontal: false),
        .swallowAndSmooth(
            dx: ScrollSample.minimumWheelStep,
            dy: -ScrollSample.minimumWheelStep
        ),
        "平滑开启时反向作用在引擎输入上，并按最小步长归一化"
    )
    checkEqual(
        sample.plan(smooth: false, reverseVertical: true, reverseHorizontal: false),
        .modifyAndPass(vertical: true, horizontal: false),
        "平滑关闭时反向作用在原事件上"
    )

    // 原地反向只改指定轴，且 point / fixedPt / line 三种字段一起翻。
    if let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: 2,
        wheel1: 10,
        wheel2: 4,
        wheel3: 0
    ) {
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 100)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 40)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 4)

        event.reverseScrollFields(
            ScrollSample(event: event),
            vertical: true,
            horizontal: false
        )
        checkEqual(
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            -100,
            "原地反向应翻转垂直点增量"
        )
        checkEqual(
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            -10,
            "原地反向应翻转垂直固定点增量"
        )
        checkEqual(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            -10,
            "原地反向应翻转垂直行增量"
        )
        checkEqual(
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            40,
            "原地反向不应动水平点增量"
        )
        checkEqual(
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            4,
            "原地反向不应动水平固定点增量"
        )
        checkEqual(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            4,
            "原地反向不应动水平行增量"
        )

        event.reverseScrollFields(
            ScrollSample(event: event),
            vertical: false,
            horizontal: false
        )
        checkEqual(
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            -100,
            "两个轴都不反向时不应改字段"
        )
    } else {
        check(false, "无法构造原地反向测试事件")
    }
}

// MARK: - 平滑滚动：引擎

private func testSmoothScrollEngine() {
    var engine = SmoothScrollEngine()
    engine.durationMs = 300
    engine.gain = 1
    engine.enqueue(dx: 0, dy: 100)

    var total = 0
    var firstPhase: ScrollPhase?
    var lastPhase: ScrollPhase?
    var elapsed = 0.0
    var monotonic = true
    var endedZero = false
    var frames = 0

    while let out = engine.tick(dt: 1.0 / 120), frames < 400 {
        frames += 1
        elapsed += 1.0 / 120
        if firstPhase == nil { firstPhase = out.phase }
        if out.dy < 0 { monotonic = false }
        total += out.dy
        lastPhase = out.phase
        if out.finished {
            endedZero = out.dx == 0 && out.dy == 0
            break
        }
    }

    checkEqual(firstPhase, .began, "首帧相位应为 began")
    checkEqual(lastPhase, .ended, "结束帧相位应为 ended")
    check(endedZero, "ended 帧应为零增量")
    check(monotonic, "输出应单调向目标走，不回头")
    checkEqual(total, 100, "累计输出应正好等于目标整数")
    check(total <= 100, "输出不应超过目标")
    check(elapsed < 1.0, "300ms 的曲线应在 1 秒内收尾，实际 \(elapsed)s")

    var run = SmoothScrollEngine()
    run.durationMs = 300
    run.enqueue(dx: 0, dy: 100)
    var progress = 0
    for _ in 0..<36 {
        if let out = run.tick(dt: 1.0 / 120) { progress += out.dy }
    }
    check(progress >= 90, "300ms 内至少完成 90pt，实际 \(progress)")

    // 指数尾部太慢时，单 tick 保底 1pt。
    var tail = SmoothScrollEngine()
    tail.durationMs = 300
    tail.enqueue(dx: 0, dy: 5)
    let first = tail.tick(dt: 0.001)
    check((first?.dy ?? 0) >= 1, "剩余 ≥1pt 时单 tick 至少 1pt，实际 \(first?.dy ?? 0)")

    // 小数余数不能丢：10 × 0.4pt 最终应输出 4pt。
    var fraction = SmoothScrollEngine()
    fraction.durationMs = 300
    for _ in 0..<10 { fraction.enqueue(dx: 0, dy: 0.4) }
    var fractionTotal = 0
    var fractionGuard = 0
    while let out = fraction.tick(dt: 1.0 / 60), fractionGuard < 600 {
        fractionGuard += 1
        fractionTotal += out.dy
    }
    checkEqual(fractionTotal, 4, "10 × 0.4pt 应最终输出 4pt")

    // 换向不清零 target：+100 再 -200，最终位置是 -100。
    var reverse = SmoothScrollEngine()
    reverse.durationMs = 300
    reverse.enqueue(dx: 0, dy: 100)
    let firstStep = reverse.tick(dt: 1.0 / 60)
    reverse.enqueue(dx: 0, dy: -200)
    var reverseTotal = firstStep?.dy ?? 0
    var reverseGuard = 0
    while let out = reverse.tick(dt: 1.0 / 60), reverseGuard < 600 {
        reverseGuard += 1
        reverseTotal += out.dy
    }
    checkEqual(reverseTotal, -100, "换向后目标应累加为 -100，而不是从 0 重来")

    engine.reset()
    check(engine.isIdle, "reset 后引擎应回到空闲")
    check(engine.tick(dt: 1.0 / 60) == nil, "空闲引擎 tick 应返回 nil")

    // 倍率必须作用在总距离上，而不只是动画速度。
    var gained = SmoothScrollEngine()
    gained.durationMs = 180
    gained.gain = 2
    gained.enqueue(dx: 0, dy: 10)
    var gainedTotal = 0.0
    var gainedGuard = 0
    while let out = gained.tick(dt: 1.0 / 120), gainedGuard < 600 {
        gainedGuard += 1
        gainedTotal += Double(out.dy)
    }
    checkClose(gainedTotal, 20, "倍率应放大总滚动距离")
}

// MARK: - 平滑滚动：存储

private func testSmoothScrollStore() {
    let suite = "com.slh.macexpert.tests.smoothscroll"
    guard let defaults = UserDefaults(suiteName: suite) else {
        check(false, "无法创建平滑滚动测试 UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = SmoothScrollStore(defaults: defaults)
    check(!store.isEnabled, "平滑滚动默认关闭")
    check(store.isSmooth, "默认开启平滑")
    check(!store.reverseVertical, "默认不反向垂直")
    check(!store.reverseHorizontal, "默认不反向水平")
    checkClose(store.durationMs, 180, "默认平滑时长 180ms")
    checkClose(store.gain, 1.0, "默认倍率 1.0")

    store.setEnabled(true)
    check(store.isEnabled, "总开关应能持久化")
    store.setSmooth(false)
    check(!store.isSmooth, "平滑开关应能持久化")
    store.setReverseVertical(true)
    store.setReverseHorizontal(true)
    check(store.reverseVertical, "垂直反向应能持久化")
    check(store.reverseHorizontal, "水平反向应能持久化")

    store.setDurationMs(9999)
    checkClose(store.durationMs, 400, "平滑时长上限应夹到 400")
    store.setDurationMs(10)
    checkClose(store.durationMs, 80, "平滑时长下限应夹到 80")

    store.setGain(9)
    checkClose(store.gain, 4.0, "倍率上限应夹到 4.0")
    store.setGain(0.01)
    checkClose(store.gain, 0.5, "倍率下限应夹到 0.5")

    check(store.accelerationEnabled, "默认开启快速滚动加速")
    checkClose(store.accelerationMax, 2.5, "默认最高加速 2.5×")
    store.setAccelerationEnabled(false)
    check(!store.accelerationEnabled, "加速开关应能持久化")
    store.setAccelerationMax(99)
    checkClose(store.accelerationMax, 10.0, "最高加速上限应夹到 10.0")
    store.setAccelerationMax(0.1)
    checkClose(store.accelerationMax, 1.5, "最高加速下限应夹到 1.5")
}

// MARK: - 平滑滚动：快速滚动加速

private func testSmoothScrollAcceleration() {
    var accel = ScrollAcceleration()
    accel.maxBoost = 2.5

    checkEqual(accel.boost(dx: 0, dy: 33.6, at: 1.0), 1.0, "第一格不加速")

    var last = 1.0
    var time = 1.0
    for _ in 0..<8 {
        time += 0.025
        last = accel.boost(dx: 0, dy: 33.6, at: time)
    }
    check(last > 1.5, "连续快速滚动应明显加速")
    check(last <= 2.5 + 0.0001, "加速不应超过最高倍率")

    checkEqual(accel.boost(dx: 0, dy: 33.6, at: 2.5), 1.0, "停手后第一格重新从 1× 开始")

    var reverse = ScrollAcceleration()
    reverse.maxBoost = 2.5
    _ = reverse.boost(dx: 0, dy: 33.6, at: 3.0)
    _ = reverse.boost(dx: 0, dy: 33.6, at: 3.02)
    checkEqual(reverse.boost(dx: 0, dy: -33.6, at: 3.04), 1.0, "换向后第一格不加速")

    var slow = ScrollAcceleration()
    slow.maxBoost = 2.5
    _ = slow.boost(dx: 0, dy: 33.6, at: 4.0)
    var slowBoost = 1.0
    for index in 1...8 {
        slowBoost = slow.boost(dx: 0, dy: 33.6, at: 4.0 + Double(index) * 0.2)
    }
    checkClose(slowBoost, 1.0, "慢速滚动应保持 1×")

    // 最高加速 10× 时，快速滚动应能接近上限，而不是被旧的 4× 夹住。
    var high = ScrollAcceleration()
    high.maxBoost = 10
    _ = high.boost(dx: 0, dy: 33.6, at: 6.0)
    var highBoost = 1.0
    for index in 1...12 {
        highBoost = high.boost(dx: 0, dy: 33.6, at: 6.0 + Double(index) * 0.02)
    }
    check(highBoost > 5.0, "最高加速 10× 时应能明显超过 5×")
    check(highBoost <= 10.0 + 0.0001, "最高加速不应超过 10×")
}

// MARK: - 翻译分类器

private func testTranslationClassifier() {
    // 中文短词 → 词典 / 英译
    let chineseWord = TranslationClassifier.decide("你好")
    checkEqual(chineseWord?.mode, .dictionary, "中文短词应走词典")
    checkEqual(chineseWord?.source, .chinese, "中文短词源语言")
    checkEqual(chineseWord?.target, .english, "中文短词目标语言")
    checkEqual(chineseWord?.label, "中文 → 英语 · 词典", "中文短词方向文案")

    checkEqual(TranslationClassifier.decide("人工智能")?.mode, .dictionary, "4 个汉字应仍走词典")
    checkEqual(TranslationClassifier.decide("中华人民共和国")?.mode, .text, "7 个汉字应走长文本")

    // 中文长句 → 长文本 / 英译
    let chineseSentence = "今天天气很好，我们去公园散步吧。"
    let longChinese = TranslationClassifier.decide(chineseSentence)
    checkEqual(longChinese?.mode, .text, "中文长句应走长文本")
    checkEqual(longChinese?.target, .english, "中文长句默认译成英文")

    // 外文单词 → 词典 / 中译
    let englishWord = TranslationClassifier.decide("hello")
    checkEqual(englishWord?.mode, .dictionary, "外文单词应走词典")
    checkEqual(englishWord?.source, .english, "外文单词源语言")
    checkEqual(englishWord?.target, .chinese, "外文单词目标语言")
    checkEqual(englishWord?.label, "英语 → 中文 · 词典", "外文单词方向文案")

    checkEqual(TranslationClassifier.decide("New York")?.mode, .dictionary, "两个词的短语应走词典")
    checkEqual(TranslationClassifier.decide("good morning everyone")?.mode, .dictionary, "三个词应走词典")
    checkEqual(TranslationClassifier.decide("this is a test")?.mode, .text, "四个词应走长文本")
    checkEqual(
        TranslationClassifier.decide("Hello, world.")?.mode,
        .text,
        "带句末标点的短语应走长文本"
    )
    checkEqual(
        TranslationClassifier.decide("A very long phrase that definitely exceeds thirty characters.")?.mode,
        .text,
        "超过 30 字符的短语应走长文本"
    )

    // 外文长句 → 长文本 / 中译
    let englishSentence = "This is a complete sentence that should be translated as a paragraph."
    let longEnglish = TranslationClassifier.decide(englishSentence)
    checkEqual(longEnglish?.mode, .text, "外文长句应走长文本")
    checkEqual(longEnglish?.target, .chinese, "外文长句默认译成中文")

    // 其他文字按外文处理
    let kana = TranslationClassifier.decide("こんにちは")
    checkEqual(kana?.source, .other, "假名应识别为外文")
    checkEqual(kana?.mode, .dictionary, "单个假名词应走词典")
    checkEqual(kana?.target, .chinese, "外文默认译成中文")
    checkEqual(kana?.label, "外文 → 中文 · 词典", "外文方向文案")

    // 长文本目标语言覆盖
    checkEqual(
        TranslationClassifier.decide(chineseSentence, longTextTarget: .chinese)?.target,
        .chinese,
        "固定中文应覆盖长文本方向"
    )
    checkEqual(
        TranslationClassifier.decide(chineseSentence, longTextTarget: .english)?.target,
        .english,
        "固定英文应覆盖中文长文本方向"
    )
    checkEqual(
        TranslationClassifier.decide(englishSentence, longTextTarget: .english)?.target,
        .english,
        "固定英文应覆盖外文长文本方向"
    )
    checkEqual(
        TranslationClassifier.decide(englishSentence, longTextTarget: .chinese)?.target,
        .chinese,
        "固定中文应覆盖外文长文本方向"
    )

    // 手动模式
    checkEqual(
        TranslationClassifier.decide("hello", mode: .text)?.mode,
        .text,
        "手动翻译应覆盖词典判断"
    )
    checkEqual(
        TranslationClassifier.decide(chineseSentence, mode: .dictionary)?.mode,
        .dictionary,
        "手动词典应覆盖长文本判断"
    )

    check(TranslationClassifier.decide("   ") == nil, "空白输入不应给出判断")
    checkEqual(TranslationClassifier.hanCount("你好世界"), 4, "汉字计数")
    checkEqual(TranslationClassifier.wordCount("hello, world"), 2, "英文词数")
    check(TranslationClassifier.endsWithTerminalPunctuation("Hello."), "句末句号应被识别")
    check(!TranslationClassifier.endsWithTerminalPunctuation("Hello,"), "逗号不算句末标点")
}

// MARK: - SSE 分块

private func testTranslationSSE() {
    var parser = TranslationSSE.Parser()
    let first = parser.feed("data: {\"a\":1}\n\ndata: {\"b\"")
    checkEqual(first, [.data("{\"a\":1}")], "半行应暂存到下一次 feed")

    let second = parser.feed(":2}\r\n\r\ndata: [DONE]\n\n")
    checkEqual(second, [.data("{\"b\":2}"), .done], "CRLF 跨块应正确拼回，并识别 [DONE]")

    var multiline = TranslationSSE.Parser()
    checkEqual(
        multiline.feed("data: line1\ndata: line2\n\n"),
        [.data("line1\nline2")],
        "多行 data 应用换行拼接"
    )

    var comment = TranslationSSE.Parser()
    checkEqual(
        comment.feed(": ping\n\ndata: x\n\n"),
        [.data("x")],
        "注释行应被忽略"
    )

    var tail = TranslationSSE.Parser()
    checkEqual(tail.feed("data: tail"), [], "没有换行结尾时不应提前派发")
    checkEqual(tail.finish(), [.data("tail")], "finish 应派发残留行")

    checkEqual(
        TranslationSSE.extractContent(from: "{\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}"),
        "你好",
        "应取 delta.content"
    )
    checkEqual(
        TranslationSSE.extractContent(from: "{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"),
        nil,
        "只有 role 时不应产出文本"
    )
    checkEqual(
        TranslationSSE.extractContent(from: "[DONE]"),
        nil,
        "[DONE] 不是内容"
    )

    let messageData = Data("{\"choices\":[{\"message\":{\"content\":\"hello\"}}]}".utf8)
    checkEqual(
        TranslationSSE.messageContent(from: messageData),
        "hello",
        "非流式应取 message.content"
    )
    checkEqual(
        TranslationSSE.messageContent(from: Data("{}".utf8)),
        nil,
        "没有 choices 时应返回 nil"
    )
}

// MARK: - 词典 JSON

private func testTranslationDictionary() {
    let fenced = """
    ```json
    {
      "word": "hello",
      "phonetic": "/həˈləʊ/",
      "senses": [
        {"partOfSpeech": "int.", "translation": "你好", "definition": "used as a greeting"},
        {"partOfSpeech": "n.", "translation": "招呼", "definition": "a greeting"}
      ],
      "examples": [
        {"source": "Hello, world!", "target": "你好，世界！"}
      ],
      "synonyms": ["hi", "greetings"]
    }
    ```
    """
    let entry = DictionaryJSON.parse(fenced)
    checkEqual(entry?.word, "hello", "词典词头")
    checkEqual(entry?.phonetic, "/həˈləʊ/", "词典音标")
    checkEqual(entry?.senses.count, 2, "词典义项数量")
    checkEqual(entry?.senses.first?.partOfSpeech, "int.", "词典词性")
    checkEqual(entry?.senses.first?.translation, "你好", "词典目标语释义")
    checkEqual(entry?.senses.first?.definition, "used as a greeting", "词典源语解释")
    checkEqual(entry?.examples.first?.source, "Hello, world!", "例句原文")
    checkEqual(entry?.examples.first?.target, "你好，世界！", "例句译文")
    checkEqual(entry?.synonyms, ["hi", "greetings"], "近义词")

    let prose = "结果如下：\n{\"word\":\"你好\",\"senses\":[{\"translation\":\"hello\",\"definition\":\"打招呼\"}]}\n以上。"
    let chinese = DictionaryJSON.parse(prose)
    checkEqual(chinese?.word, "你好", "应容忍 JSON 前后的说明文字")
    checkEqual(chinese?.senses.first?.translation, "hello", "中文词条英译")

    let flat = DictionaryJSON.parse("{\"word\":\"test\",\"translation\":\"测试\",\"definition\":\"a trial\"}")
    checkEqual(flat?.senses.count, 1, "缺少 senses 时应从顶层 translation 兜底")

    let exampleOnly = DictionaryJSON.parse("{\"word\":\"x\",\"senses\":[{\"translation\":\"y\"}],\"examples\":[\"A plain example\"]}")
    checkEqual(exampleOnly?.examples.first?.source, "A plain example", "字符串例句应保留原文")

    check(DictionaryJSON.parse("这不是 JSON") == nil, "坏 JSON 应返回 nil，交给原文回退")
    check(DictionaryJSON.parse("{\"word\":\"x\"}") == nil, "没有义项应返回 nil")
}

// MARK: - 端点与提示词

private func testTranslationEndpoint() {
    checkEqual(
        TranslationEndpoint.normalizedBase("https://api.openai.com/v1"),
        "https://api.openai.com/v1",
        "带 /v1 的地址不应重复拼接"
    )
    checkEqual(
        TranslationEndpoint.normalizedBase("https://api.openai.com/v1/"),
        "https://api.openai.com/v1",
        "结尾斜杠应去掉"
    )
    checkEqual(
        TranslationEndpoint.normalizedBase("https://api.openai.com/v1/chat/completions"),
        "https://api.openai.com/v1",
        "填完整 chat 路径时应回退到 base"
    )
    checkEqual(
        TranslationEndpoint.normalizedBase("https://api.openai.com"),
        "https://api.openai.com/v1",
        "裸域名应补 /v1"
    )
    checkEqual(
        TranslationEndpoint.normalizedBase("https://openrouter.ai/api/v1"),
        "https://openrouter.ai/api/v1",
        "已有版本段不应重复补 /v1"
    )
    checkEqual(
        TranslationEndpoint.normalizedBase("http://localhost:11434/v1"),
        "http://localhost:11434/v1",
        "本地模型地址应保留 http"
    )
    checkEqual(
        TranslationEndpoint.chatURLString("https://api.openai.com/v1"),
        "https://api.openai.com/v1/chat/completions",
        "chat 端点拼接"
    )
    checkEqual(
        TranslationEndpoint.modelsURLString("https://api.openai.com/v1/chat/completions"),
        "https://api.openai.com/v1/models",
        "models 端点拼接"
    )
    check(TranslationEndpoint.normalizedBase("ftp://example.com") == nil, "非 HTTP(S) 应拒绝")
    check(TranslationEndpoint.normalizedBase("not a url") == nil, "无 scheme 应拒绝")

    check(TranslationEndpoint.insecureReason("https://api.openai.com/v1") == nil, "HTTPS 应放行")
    check(TranslationEndpoint.insecureReason("http://localhost:11434") == nil, "localhost 应放行")
    check(TranslationEndpoint.insecureReason("http://127.0.0.1:11434") == nil, "127.0.0.1 应放行")
    check(TranslationEndpoint.insecureReason("http://example.com") != nil, "外部 http 应拒绝")

    checkEqual(TranslationHTTPError.map(status: 401, body: "bad key"), .unauthorized, "401 应映射为密钥无效")
    checkEqual(TranslationHTTPError.map(status: 404, body: "not found"), .notFound, "404 应映射为地址不对")
    checkEqual(TranslationHTTPError.map(status: 429, body: "slow down"), .rateLimited, "429 应映射为限流")
    checkEqual(TranslationHTTPError.map(status: 503, body: "down"), .server(503), "5xx 应映射为供应商异常")
    check(
        !TranslationHTTPError.snippet("Authorization: Bearer sk-secret123").contains("sk-secret123"),
        "错误摘要必须抹掉密钥"
    )

    let english = TranslationClassifier.decide("hello")!

    let requestBody = try? TranslationClient.chatBody(
        model: "gpt-4o-mini",
        messages: TranslationPrompt.messages(text: "hello", decision: english),
        stream: true,
        jsonMode: false
    )
    if let requestBody,
       let object = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any] {
        checkEqual(object["model"] as? String, "gpt-4o-mini", "请求体应带 model")
        checkEqual(object["stream"] as? Bool, true, "请求体应带 stream")
        check(object["messages"] != nil, "请求体应带 messages")
        check(object["temperature"] == nil, "不应发送 temperature")
        check(object["max_tokens"] == nil, "不应发送 max_tokens")
        check(object["response_format"] == nil, "普通请求不应带 response_format")
    } else {
        check(false, "请求体应是合法 JSON")
    }

    let dictionaryMessages = TranslationPrompt.messages(text: "hello", decision: english)
    checkEqual(dictionaryMessages.count, 2, "应构造 system + user 两条消息")
    checkEqual(dictionaryMessages[0].role, "system", "第一条是 system")
    checkEqual(dictionaryMessages[1].role, "user", "第二条是 user")
    checkEqual(dictionaryMessages[1].content, "hello", "user 消息应原样携带输入")
    check(dictionaryMessages[0].content.contains("JSON"), "词典提示词应要求 JSON")
    check(dictionaryMessages[0].content.contains("senses"), "词典提示词应包含 senses 字段")
    check(dictionaryMessages[0].content.contains("中文"), "英文词条应要求中文释义")

    let chinese = TranslationClassifier.decide("你好")!
    let chinesePrompt = TranslationPrompt.system(chinese)
    check(chinesePrompt.contains("拼音"), "中文词条应要求拼音")
    check(chinesePrompt.contains("英语"), "中文词条应要求英文翻译")

    let longEnglish = TranslationClassifier.decide("This is a long sentence that needs translation.")!
    let textPrompt = TranslationPrompt.system(longEnglish)
    check(textPrompt.contains("中文"), "长文本提示词应包含目标语言")
    check(textPrompt.contains("Markdown"), "长文本提示词应要求保留 Markdown")
    check(textPrompt.contains("代码块"), "长文本提示词应要求保留代码块")
}

// MARK: - 翻译配置存储

private func testTranslationStore() {
    let suite = "com.slh.macexpert.tests.translation"
    guard let defaults = UserDefaults(suiteName: suite) else {
        check(false, "无法创建翻译测试 UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suite)

    let store = TranslationStore(defaults: defaults)
    check(store.enabled, "翻译默认启用")
    checkEqual(store.baseURL, "https://api.openai.com/v1", "默认 Base URL")
    checkEqual(store.model, "gpt-4o-mini", "默认模型")
    checkEqual(store.longTextTarget, .auto, "默认长文本目标语言")
    check(store.streamOutput, "默认开启流式输出")

    store.enabled = false
    store.baseURL = "http://localhost:1234/v1"
    store.model = "local-model"
    store.longTextTarget = .english
    store.streamOutput = false
    check(!store.enabled, "开关应能持久化")
    checkEqual(store.baseURL, "http://localhost:1234/v1", "Base URL 应能持久化")
    checkEqual(store.model, "local-model", "模型应能持久化")
    checkEqual(store.longTextTarget, .english, "目标语言应能持久化")
    check(!store.streamOutput, "流式输出开关应能持久化")
    check(!TranslationStore(defaults: defaults).streamOutput, "流式输出关闭状态应能重新读取")

    defaults.removePersistentDomain(forName: suite)
}

// MARK: - 翻译密钥文件

private func testTranslationSecretStore() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacExpert-TranslationSecret-\(UUID().uuidString)", isDirectory: true)
    let file = root.appendingPathComponent("translation.key")
    let store = TranslationSecretStore(fileURL: file)
    defer { try? FileManager.default.removeItem(at: root) }

    checkEqual(store.load(), "", "密钥文件不存在时返回空")
    check(store.save("  sk-test-123  "), "保存密钥应成功")
    checkEqual(store.load(), "sk-test-123", "读取密钥应去掉首尾空白")

    if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
       let permissions = attrs[.posixPermissions] as? NSNumber {
        checkEqual(permissions.intValue & 0o777, 0o600, "密钥文件权限应为 0600")
    } else {
        check(false, "无法读取密钥文件权限")
    }

    if let attrs = try? FileManager.default.attributesOfItem(atPath: root.path),
       let permissions = attrs[.posixPermissions] as? NSNumber {
        checkEqual(permissions.intValue & 0o777, 0o700, "密钥目录权限应为 0700")
    } else {
        check(false, "无法读取密钥目录权限")
    }

    check(store.save(""), "保存空 Key 应删除密钥文件")
    check(!FileManager.default.fileExists(atPath: file.path), "空 Key 应删除文件")
    checkEqual(store.load(), "", "删除后读取应为空")
}

// MARK: - 版本比较

private func testAppVersion() {
    check(AppVersion("0.1.0")! < AppVersion("0.3.0")!, "0.1.0 应小于 0.3.0")
    check(AppVersion("v0.3.0")! == AppVersion("0.3.0")!, "v 前缀应被忽略")
    check(AppVersion("1.0")! == AppVersion("1.0.0")!, "缺失的版本段应按 0 处理")
    check(AppVersion("0.3.0-beta")! < AppVersion("0.3.0")!, "预发布版应小于正式版")
    check(AppVersion("1.2.3")! > AppVersion("1.2")!, "1.2.3 应大于 1.2")
    check(AppVersion("not-a-version") == nil, "无数字的版本号应解析失败")
}

// MARK: - 入口

@main
struct UnitTests {
    static func main() {
        print("== MacExpert 单元测试 ==")

        testClean()
        testDerivedParameters()
        testFeatureRegistry()
        testHotkeyDescriptions()
        testKeyMapping()
        testSmoothScrollClassification()
        testSmoothScrollReverse()
        testSmoothScrollEngine()
        testSmoothScrollStore()
        testSmoothScrollAcceleration()
        testTranslationClassifier()
        testTranslationSSE()
        testTranslationDictionary()
        testTranslationEndpoint()
        testTranslationStore()
        testTranslationSecretStore()
        testAppVersion()

        if failures == 0 {
            print("✅ 全部通过（\(checks) 项检查）")
            exit(0)
        } else {
            print("❌ \(failures)/\(checks) 项检查失败")
            exit(1)
        }
    }
}

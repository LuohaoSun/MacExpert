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
    checkEqual(Feature.allCases, [.typeClip, .keyMapping, .translate], "Feature.allCases 顺序与内容")

    check(Feature.typeClip.isAvailable, "TypeClip 已注册模块，应可用")
    check(!Feature.keyMapping.isAvailable, "按键映射尚未注册模块，应不可用")
    check(!Feature.translate.isAvailable, "热键翻译尚未注册模块，应不可用")

    for feature in Feature.allCases {
        check(!feature.title.isEmpty, "\(feature.rawValue) 的标题不应为空")
        check(!feature.subtitle.isEmpty, "\(feature.rawValue) 的副标题不应为空")
        check(!feature.icon.isEmpty, "\(feature.rawValue) 的图标名不应为空")
        check(!feature.id.isEmpty, "\(feature.rawValue) 的 id 不应为空")
    }

    checkEqual(Feature.typeClip.title, "剪贴板敲入", "TypeClip 标题")
    checkEqual(Feature.keyMapping.title, "按键映射", "按键映射标题")
    checkEqual(Feature.translate.title, "热键翻译", "热键翻译标题")

    let typeClip = MainSection.feature(.typeClip)
    checkEqual(typeClip.id, "typeClip", "MainSection id 应使用 feature.rawValue")
    checkEqual(typeClip.title, Feature.typeClip.title, "MainSection 标题应转发 feature")
    checkEqual(typeClip.subtitle, Feature.typeClip.subtitle, "MainSection 副标题应转发 feature")
    checkEqual(typeClip.icon, Feature.typeClip.icon, "MainSection 图标应转发 feature")
    check(typeClip.badge == nil, "可用功能不应有「规划中」徽章")
    check(typeClip.isAvailable, "TypeClip 的 MainSection 应可用")

    let keyMapping = MainSection.feature(.keyMapping)
    checkEqual(keyMapping.badge, "规划中", "未注册功能应显示「规划中」")
    check(!keyMapping.isAvailable, "未注册功能的 MainSection 应不可用")

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

// MARK: - 入口

@main
struct UnitTests {
    static func main() {
        print("== MacExpert 单元测试 ==")

        testClean()
        testDerivedParameters()
        testFeatureRegistry()
        testHotkeyDescriptions()

        if failures == 0 {
            print("✅ 全部通过（\(checks) 项检查）")
            exit(0)
        } else {
            print("❌ \(failures)/\(checks) 项检查失败")
            exit(1)
        }
    }
}

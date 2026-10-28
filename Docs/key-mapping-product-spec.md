# 鼠标按键映射 · 产品规格

> 目标版本：0.3.0（build 4）  
> 状态：已实现，等待真机验收  
> 依赖：辅助功能权限（与「剪贴板敲入」共用，不新增 TCC 权限项）

---

## 1. 一句话

把鼠标侧键、中键和额外按键变成任意键盘组合键，全局生效；按下鼠标键时拦截原行为，只发送设定好的快捷键。

## 2. 用户故事

- 我在远程桌面/堡垒机里，鼠标侧键没有后退/前进，想把它变成 `⌘[` / `⌘]`。
- 我想用侧键触发复制、粘贴、任务控制，不离开当前应用。
- 我有一只多键鼠标，厂商驱动不好用，想用系统级映射统一管理。
- 我临时不想让映射生效，需要一键暂停，让侧键恢复默认行为。

## 3. 范围

### 0.3.0 做

- 全局映射：鼠标按钮 2–31（中键、侧键、额外键）→ 键盘组合键。
- 每条映射包含：触发键、快捷键、名称、启用开关。
- 单击触发：按下鼠标键立即触发。
- 添加、编辑、删除、单条启用/停用。
- 总开关；菜单栏快速暂停。
- 权限引导、监听自动恢复（tap 超时、睡眠唤醒、授权变化）。
- 按键探测与最近触发记录（内存，最多 20 条）。
- 空状态、预设、冲突校验。
- 单元测试、离屏预览、README 更新。

### 0.3.0 不做（预留）

- 双击、长按、组合手势触发。
- 分应用配置。
- 多动作序列/宏。
- 鼠标滚轮、手势、绘图板。
- 媒体键、文本片段、启动 App 作为动作（0.3.0 只做键盘组合键）。
- 配置导入/导出。
- “同时保留原按键行为”（拦截和原样放行二选一）。

## 4. 核心交互

### 4.1 首次使用

1. 侧栏出现「鼠标按键映射」，不再显示“规划中”。
2. 未授权时顶部出现橙色权限条；状态卡显示“等待辅助功能权限”。此时仍可添加和编辑映射。
3. 没有映射时展示空状态：鼠标图标、一句说明、“添加第一条映射”按钮，以及 3 条预设：
   - 侧键 1 → `⌘[` 后退
   - 侧键 2 → `⌘]` 前进
   - 中键 → `⌃⌘V` 敲入剪贴板
4. 点预设或“添加映射”进入编辑弹窗。

### 4.2 添加/编辑映射

**鼠标按键**

- 点选：中键、侧键 1、侧键 2、侧键 3。
- 正式版支持在弹窗里按下鼠标键自动捕获，并显示系统按钮编号，例如“已捕获按钮 3（多数鼠标的侧键 1）”。
- 按钮命名只用于展示，实际按 `CGEvent` 的 `mouseEventButtonNumber` 匹配：
  - 2 = 中键
  - 3 = 侧键 1（多数鼠标的后退键）
  - 4 = 侧键 2（多数鼠标的前进键）
  - 5+ = 额外的鼠标键
- 选择中键时提示：中键常被用于滚动、新标签页等，确认要拦截再保存。

**发送快捷键**

- 正式版用临时 session 键盘 tap 录制，录制期间吞掉按键事件，避免边录边触发。
- 本地 `NSEvent` 监听看不到被系统抢先处理的 ⌃← / ⌃→（切换桌面），因此录制用 CGEventTap 在系统处理前抓键。
- 极少数由系统在最底层接管的组合仍可能录不到，弹窗内给出提示。
- 原型用常用键选择器演示交互，正式版支持任意键。

**名称**

- 可留空；留空时自动使用常见组合名：
  - `⌘C` → 复制、`⌘V` → 粘贴、`⌘X` → 剪切、`⌘Z` → 撤销
  - `⌘[` → 后退、`⌘]` → 前进
  - `⌃⌘V` → 敲入剪贴板
  - `⌃↑` → 任务控制、`⌃↓` → App Exposé
- 用户手填的名称优先，不再自动覆盖。

**校验**

- 同一鼠标键只能有一条映射；编辑时排除自己。
- 无修饰键的普通字符键（字母、数字、符号）阻止保存，提示“会在所有输入框里输入字符”。
- 允许无修饰键的安全键：Return、Tab、Esc、Space、Delete、方向键、F1–F12、Home、End、PageUp、PageDown。
- 保存后立即生效，弹窗关闭并显示 toast。
- 删除映射需要二次确认（原型里直接删除）。

### 4.3 日常使用

- 按下已映射的鼠标键：拦截 down/up/drag，发送快捷键；状态卡显示“最近：侧键 1 → ⌘C（Safari）”。
- 按下未映射的鼠标键：原样放行。
- 总开关关闭：停止监听，所有鼠标键恢复默认。
- 单条映射关闭：该键放行，其余映射不受影响。
- 菜单栏新增“启用鼠标按键映射”复选项，与主窗口总开关联动。
- 所有映射都关闭或为空：不创建监听，状态卡提示“没有生效的映射”。

### 4.4 权限与异常

| 场景 | 行为 |
| --- | --- |
| 未授权 | 不创建事件 tap；页面显示橙色权限条；不反复弹系统提示 |
| 授权后 | App 激活、系统唤醒、tap 被系统暂停时自动重建监听 |
| tap 超时/被系统禁用 | 回调里立即 `CGEvent.tapEnable`；连续失败显示“监听未启动”+ 重启按钮 |
| 睡眠唤醒 | 通过 `NSWorkspace.didWakeNotification` 重建 |
| 安全输入（密码框） | 不做特殊拦截；系统会丢弃注入的按键，不重试 |
| 厂商驱动占用侧键 | 诊断区提示先去驱动里设为“无操作” |
| 鼠标侧键发送的是键盘事件 | 无法被鼠标监听捕获，文档明确说明 |
| 多只鼠标按钮编号相同 | 无法区分设备，文档说明 |

## 5. 数据模型

```swift
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16          // Carbon 虚拟键码，按下时的物理键
    var modifiers: ModifierSet   // command / shift / option / control
    var keyLabel: String         // 展示用，例如 "C"、"↩"、"F5"
}

struct KeyMapping: Codable, Identifiable, Equatable {
    var id: UUID
    var button: Int              // CGEvent mouseEventButtonNumber：2 中键，3+ 侧键
    var combo: KeyCombo
    var name: String
    var enabled: Bool
}
```

持久化：

- `keyMappings.v1`：JSON 数组，存 `UserDefaults.standard`。
- `keyMappingEnabled`：总开关。
- `keyMappingSendDelayMs`：发送间隔，默认 30ms，可调 0–200ms。
- 解码失败时从空配置启动并写一行日志，不崩溃。
- 存储键带版本号，后续可迁移。

## 6. 技术方案

### 6.1 MouseButtonTap

- `CGEvent.tapCreate`，位置 `.cgSessionEventTap`，插入 `.headInsertEventTap`，选项 `.defaultTap`（需要修改/吞事件）。
- 监听 `otherMouseDown`、`otherMouseUp`、`otherMouseDragged`。
- 只处理 `buttonNumber >= 2`。
- 命中映射时吞掉 down，并记录该按钮；后续 up/drag 一并吞掉，避免残留事件或误拖拽。
- 未命中时原样返回事件，不影响正常鼠标操作。
- 回调处理 `.tapDisabledByTimeout` / `.tapDisabledByUserInput`，立即重新 `tapEnable`。
- 事件源挂到主 RunLoop 的 `.commonModes`，菜单打开、窗口拖拽时仍然工作。
- 编辑弹窗录制鼠标键时进入 capture 模式：优先把下一个按钮事件交给录制器并吞掉，不触发已有映射。
- 预期只需要辅助功能权限。实现时真机验证；若系统额外要求输入监控，在权限卡里补一行说明，不改变产品流程。

### 6.2 ShortcutSender

- 复用 `EventInjector`，补上 Command/Control 的设备位（左键位）。
- 系统快捷键（⌃← / ⌃→、⌃↑ 等）用私有事件源 + `.cghidEventTap` 投递；只投到 session 层时，事件会进入前台 App，但 WindowServer 不会执行系统快捷键（表现为应用里能收到 ⌃←，桌面不切换）。
- 发送顺序：`⌃⌥⇧⌘` 按下 → 字符键 down/up → 反向抬起修饰键。
- 字符键事件带 `keyCode + flags`，不写 Unicode 串；方向键、功能键没有 Unicode，也能正常发送。
- 串行后台队列 + 可调发送间隔，默认 30ms，避免远程桌面把修饰键和字符键合并/丢修饰键。
- 记录已按下的修饰键；取消或退出时补发抬起，防止修饰键卡住。
- 事件 tap 回调只做查表和入队，不睡眠、不阻塞主线程。

### 6.3 Feature 接入

- `KeyMappingFeature: ObservableObject`，实现 `FeatureModule`：
  - `install()`：读取配置，按需启动监听。
  - `onActivated()`：重新检查权限，必要时重建监听。
  - `prepareForTermination()`：停止监听、释放修饰键。
  - `statusLine`：只在监听失败时返回提示，避免抢走菜单栏状态行。
- `FeatureRegistry.modules` 增加 `KeyMappingFeature.shared`。
- `MainWindowView` 的 `.feature(.keyMapping)` 路由到真正的 `KeyMappingView`。
- 删除 `PlaceholderViews.swift` 里的 `KeyMappingPrototypeView`。
- 菜单栏增加“启用鼠标按键映射”复选项。
- `AppState` 增加 `keyMapping` 引用，保持与 `typeClip` 一致。

### 6.4 UI 文件

- `Sources/Features/KeyMapping/KeyMapping.swift`：模型、校验、存储。
- `Sources/Features/KeyMapping/MouseButtonTap.swift`：事件 tap、按钮吞噬状态机、诊断回调。
- `Sources/Features/KeyMapping/ShortcutSender.swift`：串行注入、修饰键清理。
- `Sources/Features/KeyMapping/KeyMappingFeature.swift`：功能状态、总开关、最近触发。
- `Sources/Features/KeyMapping/KeyMappingFeature+Module.swift`：`FeatureModule` 实现。
- `Sources/UI/KeyMappingView.swift`：页面。
- `Sources/UI/KeyMappingEditor.swift`：编辑弹窗。
- 复用 `PageScaffold`、`CardSurface`、`SettingsRow`、`PermissionBanner`、`KeyCap`、`HotkeyCaps`。
- 新增 `MouseButtonBadge`（鼠标图标 + 侧键名）作为页面和弹窗共用的小零件。

### 6.5 测试

纯逻辑单测（不启动 App、不读剪贴板、不注册热键、不发 CGEvent）：

- `KeyMapping` Codable 往返。
- 同一鼠标键冲突检测；编辑时排除自己。
- 无修饰键普通字符键被拒绝；安全键放行。
- 快捷键展示顺序与特殊键名称。
- 鼠标按钮编号 → 展示名称。
- `ButtonPressTracker`：down 吞掉后 up/drag 也吞掉，未命中不吞。
- `MappingResolver`：只匹配启用的映射；总开关关闭时不匹配。
- 发送间隔边界值。

### 6.6 预览、文档与发布

- `PreviewRenderer` 注入 3 条示例映射，随 `Feature.allCases` 自动多渲染一张「鼠标按键映射」页。
- README 增加功能说明、权限说明、已知限制、目录树。
- `Info.plist` 版本升到 0.3.0 / build 4。
- release 构建继续排除 `Sources/Dev`，自动扫描 dev hook 字面量。
- 不新增 TCC 权限项，不新增 entitlements。

## 7. 验收标准

- [ ] 添加 3 条映射，退出并重启 App 后仍然存在。
- [ ] 按下侧键 1 只发送 `⌘C`，Safari 不会后退。
- [ ] 按下未映射的侧键 2，浏览器正常前进。
- [ ] 关闭单条映射，该键恢复默认行为。
- [ ] 关闭总开关或菜单栏开关，所有映射键恢复默认。
- [ ] 未授权时显示权限条；授权后无需重启即可生效。
- [ ] 睡眠唤醒、tap 超时后监听自动恢复。
- [ ] 冲突触发键、无修饰字符键被阻止保存。
- [ ] 空状态三条预设可一键进入编辑。
- [ ] `./build.sh test` 通过；`./build.sh release` 无 dev hook；离屏预览正常。
- [ ] 不新增 TCC 权限项。
- [ ] 默认日志不记录快捷键内容，只记录触发统计。

## 8. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 厂商驱动先截走侧键 | 诊断区显示“没有收到鼠标事件”；文档提示在驱动里设为“无操作” |
| 鼠标侧键发送键盘事件 | 无法支持，编辑页和 README 明确说明 |
| 中键被拦截影响滚动/新标签页 | 编辑时提示；默认不预置中键映射 |
| 远程桌面丢修饰键 | 发送间隔可调，默认 30ms |
| 安全输入丢弃注入按键 | 不重试、不报错；状态卡只记录最近触发 |
| 多鼠标按钮编号相同 | 无法区分，文档说明 |
| 全局拦截误伤 | 总开关 + 单条开关 + 菜单栏暂停；删除映射立即释放 |
| tap 回调阻塞主线程 | 只查表 + 入队，注入放在后台串行队列 |
| 修饰键卡住 | 发送器跟踪按下状态，取消/退出时补发抬起 |

## 9. 实施拆分

1. 模型、校验、存储 + 单测。
2. `MouseButtonTap` + 按钮吞噬状态机 + 诊断。
3. `ShortcutSender` + `EventInjector` 扩展。
4. `KeyMappingFeature` + 菜单栏开关 + 注册表接入。
5. `KeyMappingView` + 编辑弹窗 + 空状态 + 权限条。
6. 预览、README、版本号、构建验证、安装重启。

前 3 步可并行；第 4 步依赖 1–3；第 5 步依赖 4；第 6 步最后做。

## 10. 审核决策（推荐默认值）

1. **触发方式**：0.3.0 只做单击（推荐）；双击/长按放 0.4，因为它们必须延迟原事件，会带来可感知延迟。
2. **原行为**：默认拦截（推荐）；“同时保留”不做，避免一次按键触发两个动作。
3. **作用范围**：全局（推荐）；分应用配置放 0.4。
4. **单键限制**：普通字符键必须带修饰键；Return/Tab/Esc/Space/Delete/方向键/F 键例外（推荐）。
5. **中键**：纳入可映射范围（推荐），但默认不预置，编辑时提示影响。
6. **暂停入口**：主窗口总开关 + 菜单栏复选项（推荐）。
7. **发送间隔**：默认 30ms，可在高级里调 0–200ms（推荐）。
8. **空状态预设**：给 3 条（后退/前进/敲入剪贴板，推荐）。
9. **诊断**：按键探测 + 最近触发，默认折叠（推荐）。
10. **版本号**：0.3.0 / build 4（推荐）。

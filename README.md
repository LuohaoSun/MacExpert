# MacExpert

自用的 macOS 菜单栏小工具集。菜单栏只放模块开关、打开主窗口和退出；完整功能与设置都放在主窗口里，多个小功能用侧边栏切换。

当前正式版为 **1.0.0**，发布说明见 [Docs/RELEASE_NOTES-1.0.0.md](Docs/RELEASE_NOTES-1.0.0.md)。

## 功能

| 功能 | 说明 | 状态 |
| --- | --- | --- |
| 敲入 | 把剪贴板文本逐键敲入当前应用（原 TypeClip） | 可用 |
| 鼠标按键映射 | 鼠标侧键/中键 → 键盘组合键 | 可用 |
| 平滑滚动 | 鼠标滚轮平滑 + 垂直/水平反向 | 可用 |
| 翻译 | ⌥Space → 输入文本 → 双语词典或译文 | 可用 |

菜单栏原生菜单只保留「启用剪贴板敲入」「启用鼠标按键映射」「启用平滑滚动」「打开主窗口」「检查更新…」「退出」。权限状态、剪贴板摘要、敲入/中断动作，以及敲入速度、输入法、开机自启、诊断日志等配置，都在主窗口里。

菜单栏和 App 菜单里的「检查更新…」会查询 GitHub Releases 的最新正式版；发现新版本时打开对应发布页，不自动下载或安装。

主窗口打开时会临时显示 Dock 图标和 App 菜单；关闭窗口后回到纯菜单栏状态，不占用 Dock。

「敲入」完整继承了 TypeClip 的能力：

- **键码优先注入 + Unicode 回退**：先用 `UCKeyTranslate` 按当前键盘布局反查键码、真实地合成按键事件；布局敲不出的字符（汉字/emoji）回退 Unicode 注入。`#`、`@` 这类 Shift 符号在堡垒机里不会退化成裸数字。
- **修饰键加固**：连续同修饰字符整段按住 Shift；修饰键延迟保底 100ms；发字符前按 `flagsState` 自愈补发，适应远程端登记修饰状态慢的问题。
- 两个可调维度：**敲入速度**（字符间隔、按住时长、随机抖动、修饰键延迟都由它派生）与 **输入法** 三态（不动 / 切英文 / 切英文并恢复）。
- 敲入过程中再按一次热键 = 中断。
- 开机自启、剪贴板预览、进度显示、诊断日志。

「鼠标按键映射」把鼠标侧键和中键变成全局快捷键：

- 监听系统鼠标事件里的按钮 2–31，默认拦截原按键行为，只在命中映射时发送组合键。
- 支持单击映射；中键、侧键分别对应系统按钮 2 / 3 / 4，编辑弹窗里会显示原始编号。
- 可录制任意带修饰键的组合；Return、Tab、Esc、空格、删除、方向键和 F1–F12 允许不带修饰键，普通字符键必须带修饰键。
- 录制时临时启用键盘事件 tap，⌃← / ⌃→ 这类会被系统先拿去切换桌面的组合也能录到。
- 映射在侧键**松开后**发送快捷键，避免和鼠标按下事件抢顺序；发送前再留 30ms 让系统处理完鼠标事件。
- 发送系统快捷键时走私有事件源 + HID 层，所以侧键映射到系统快捷键时能进入 WindowServer，而不只是把按键送进前台 App。
- macOS 对合成 `⌃← / ⌃→` 这种系统保留快捷键支持不稳定；如果经常失效，建议把系统设置里的「左/右切换桌面」改成 `⌃1 / ⌃2`，再把映射改成对应组合。
- 发送间隔默认 30ms、可调 0–200ms，方便远程桌面/堡垒机登记修饰键状态。
- 与敲入共用辅助功能权限；映射、总开关和发送间隔都落在 `UserDefaults`，重启后保留。

「平滑滚动」只接管鼠标滚轮，替代 iScroll / Mos 一类工具：

- 滚轮增量先累加到目标位置，再按指数曲线逐帧追过去，松手后不会突然停住。
- 垂直、水平方向可以分别反向；平滑关闭时直接在原事件上改字段并放行，不吞事件、零延迟。
- 平滑时长 80–400ms、滚动倍率 0.5–4.0 可调；平滑关闭时时长和倍率置灰。一格滚轮会先折算到至少 33.6pt 的基准距离，避免不少鼠标只报 1pt 时滚起来发滞；倍率再乘在这个基准上。
- 快速滚动加速：根据滚轮速度（点/秒）动态加成，慢速保持 1×，连续快滚时逐步升到设定的最高倍率（默认 2.5×，可调 1.5–10×）；最终距离 = 滚动倍率 × 加速倍率，停手或换向自动重新计算。
- 触控板、Magic Mouse 以及带 `phase` / `momentumPhase` 的手势事件一律原样放行；只看 `isContinuous` 会误伤高分辨率滚轮鼠标。
- ⌘+滚轮是缩放，一律不接管。所有合成事件带固定标记，tap 看到自己的事件会放行，不会自激。
- 页面里内置一块「试一试」区域，可以直接感受平滑和反向。

## 安装

要求：macOS 15+，Apple 芯片。

1. 从 [Releases](https://github.com/LuohaoSun/MacExpert/releases) 下载最新的 DMG（文件名形如 `MacExpert-<版本>.dmg`，以 Releases 页面上的版本为准）。
2. 打开 DMG，把 `MacExpert.app` 拖进「应用程序」。
3. 首次打开请右键 →「打开」（本包未公证，直接双击会被 Gatekeeper 拦下）。
4. 授权：系统设置 → 隐私与安全性 → 辅助功能 → 开启 MacExpert。首次启动会弹出系统授权提示；也可以从菜单栏选「打开主窗口」，在窗口里的权限卡片处理。
5. 日常配置：从菜单栏选「打开主窗口」，敲入速度、输入法、开机自启、诊断日志都在窗口里。主窗口打开时会出现 Dock 图标和 App 菜单，关闭后回到菜单栏常驻。
6. 确认菜单栏里的「启用剪贴板敲入」已勾选。复制文本 → 切到目标窗口（远程桌面 / 堡垒机 / 虚拟机）→ 按 **⌃⌘V** 敲入；按 **⌃⌘↩** 敲入并在结尾补一个回车。
7. 敲入过程中再按一次 **⌃⌘V** 或 **⌃⌘↩** 可中断。
8. 鼠标按键映射：打开主窗口 → 「鼠标按键映射」→ 添加映射。点一下鼠标键区域再按侧键可自动捕获，也可以直接选；然后点快捷键区域录制组合键。保存后立即生效，原侧键行为会被拦截。
9. 平滑滚动：打开主窗口 → 「平滑滚动」→ 打开「启用」。之后鼠标滚轮的滚动会变平滑；需要反向时再打开垂直/水平反向。触控板、Magic Mouse 和 ⌘+滚轮不受影响。

## 从源码构建

只需要 Xcode Command Line Tools，不需要完整 Xcode：

```sh
./build.sh dev       # 开发构建：含 dev 钩子，仅本机调试用
./build.sh release   # 发布构建：编掉全部 dev 钩子
./build.sh test      # 只跑纯逻辑单测，不启动 App、不碰剪贴板
./make-dmg.sh        # 打一个带拖拽安装引导的 DMG（自动先做 release 构建）
```

> 构建固定最低 macOS 15（`-target arm64-apple-macosx15.0`），同时把 Mach-O 的 `LC_BUILD_VERSION` 标成 `-platform_version macos 15.0 <当前 SDK>`。`build.sh` 会打印 Info.plist 里的版本号，release 模式还会断言 `LSMinimumSystemVersion` 必须是 15.0。

### 签名

`build.sh` 的 dev 和 release 都会优先使用本机自签证书，找不到才退回 adhoc：

- 默认 identity 是 `MacExpert Local Signing`，可用 `MACEXPERT_SIGN_IDENTITY` 覆盖。
- 第一次使用前可以运行 `./Scripts/setup-dev-signing.sh`（幂等，只操作登录钥匙串和用户域信任，不需要 sudo）。它会生成 RSA 2048、10 年有效、带 `codeSigning` 用途的自签证书并导入 `login.keychain-db`。
- 自动信任失败时，按脚本提示在「钥匙串访问」里手动把「代码签名」设为「始终信任」即可。
- 没有自签证书时退回 adhoc：adhoc 的 cdhash 每次重编都会变，系统会要求重新授权辅助功能；自签 identity 则稳定得多。

开发构建的额外入口：

```sh
# 把主窗口各页在浅色/深色下渲染成 PNG，检查布局
build/MacExpert.app/Contents/MacOS/MacExpert --preview build/preview

# 检查辅助功能权限、键位表大小、文本清洗
build/MacExpert.app/Contents/MacOS/MacExpert --selfcheck

# 经分布式通知驱动一次敲入（需要常驻实例，等价于按热键）
build/MacExpert.app/Contents/MacOS/MacExpert --notify-drive

# 冒烟测试：验证中英文 / Shift 符号 / 换行能完整敲进另一个应用
# 会短暂打开测试窗口并覆盖剪贴板（测试前备份纯文本，退出时恢复），
# 需要终端已有辅助功能权限；接收窗口时长按 dev 的 paceMs 自动估算
./Tests/smoke.sh
```

> `--notify-drive` 没有来源校验：本机任何进程都能借此让常驻实例替它敲键盘，等于借用 MacExpert 的 TCC 授权。因此它只在 dev 构建里存在，`release` 构建会从 `Sources` 里自动扫出所有 `--xxx` 开关和 `com.slh.macexpert.drive` 通知名，逐一用 `strings` 校验二进制中不存在。

## 目录结构

```
Sources/
├── MacExpertApp.swift        # @main、菜单栏入口、dev 钩子
├── Core/
│   ├── AppState.swift        # Feature 注册表、全局状态、权限、主窗口路由
│   ├── FeatureModule.swift   # FeatureModule 协议 + FeatureRegistry
│   ├── MainMenu.swift        # 主窗口打开时的 App / 编辑 / 窗口菜单
│   ├── HotkeyCenter.swift    # Carbon 全局热键
│   └── AppLog.swift          # ~/Library/Logs/MacExpert.log（0600）
├── Features/
│   ├── Shared/
│   │   ├── EventInjector.swift  # CGEvent 事件原语（修饰键 / 字符 / Unicode）
│   │   └── TimelinePlayer.swift # 绝对时刻时间表播放器
│   ├── KeyMapping/
│   │   ├── KeyMapping.swift         # 组合键模型、键帽文案、校验、存储
│   │   ├── MouseButtonTap.swift     # CGEventTap 监听/拦截鼠标侧键
│   │   ├── ShortcutSender.swift     # 串行队列发送组合键、兜底释放修饰键
│   │   ├── KeyMappingEditorModel.swift # 编辑弹窗状态与快捷键录制
│   │   ├── KeyMappingFeature.swift  # 功能状态、映射增删改、事件分发
│   │   └── KeyMappingFeature+Module.swift # 实现 FeatureModule
│   ├── SmoothScroll/
│   │   ├── SmoothScrollSample.swift  # 滚轮样本、分类、反向、处理方案
│   │   ├── SmoothScrollEngine.swift  # 纯插值引擎（显式 dt）
│   │   ├── SmoothScrollStore.swift   # UserDefaults 设置与范围夹取
│   │   ├── ScrollTap.swift           # CGEventTap 监听滚轮、唤醒重启
│   │   ├── ScrollPoster.swift        # 合成像素滚轮事件并投递
│   │   ├── SmoothScrollFeature.swift # 功能状态、引擎/计时器、最近输入
│   │   └── SmoothScrollFeature+Module.swift # 实现 FeatureModule
│   └── TypeClip/
│       ├── TyperEngine.swift        # 时间表驱动的逐键注入引擎
│       ├── Keymap.swift             # 当前键盘布局 → 键码反查、输入法切换
│       ├── TypeClipFeature.swift    # 功能状态、速度派生、剪贴板摘要
│       ├── TypeClipFeature+Module.swift # 实现 FeatureModule、注册热键
│       └── TypeClipPhase+UI.swift   # 敲入状态 → 界面文案/颜色
├── UI/
│   ├── Theme.swift                 # 设计令牌与卡片/键帽/徽章等零件
│   ├── MenuBarMenu.swift           # 菜单栏原生菜单：模块开关、主窗口、退出
│   ├── MainWindowController.swift  # 主窗口入口
│   ├── WindowActivator.swift       # 窗口激活策略：Dock/App 菜单
│   ├── NativeSidebarSplit.swift    # EZS 同款原生 NSSplitViewController 侧栏
│   ├── MainWindowView.swift        # 主窗口 + 侧栏 + 功能路由
│   ├── PageComponents.swift        # 功能页共用的分区/卡片组件
│   ├── TypeClipView.swift          # 敲入功能页
│   ├── KeyMappingView.swift        # 鼠标按键映射页
│   ├── KeyMappingEditor.swift      # 鼠标按键映射编辑弹窗
│   ├── SmoothScrollView.swift      # 平滑滚动页
│   ├── TranslationView.swift       # 热键翻译配置页
│   └── SettingsView.swift          # 权限、开机自启、日志、关于
└── Dev/
    └── PreviewRenderer.swift # 仅 dev：跟着 Feature.allCases 渲染各页 PNG

Tests/
├── UnitTests.swift   # 纯逻辑单测（清洗、速度派生、功能注册表、按键映射、平滑滚动）
├── run-tests.sh      # swiftc 编译并运行单测（./build.sh test 会转到这里）
├── TypeTarget.swift  # 冒烟测试的接收窗口
└── smoke.sh          # 端到端敲入测试

Scripts/
└── setup-dev-signing.sh # 创建并信任本机自签代码签名证书（幂等）
```

新增功能时：在 `Feature` 里加一个 case → 实现 `FeatureModule`（状态、热键、生命周期）→ 注册到 `FeatureRegistry.modules` → 在 `MainWindowView` 的路由里接上视图。可用性、菜单栏状态行和主窗口徽章都会自动跟着注册表走。

## 已知限制

- 最低 macOS 15，仅构建 arm64 slice（Apple 芯片）。
- 未公证：他人首次打开需要右键「打开」。
- 签名是自签或 adhoc：替换安装后通常需要在「辅助功能」里重新授权；用 `Scripts/setup-dev-signing.sh` 固定自签 identity 可以减少 dev 重编后的重复授权，但换证书或清理钥匙串后仍需重新授权。
- 如果远程端完全拦截合成键盘事件，MacExpert 无法绕过（那是目标系统的主动防护）。
- 鼠标按键映射目前只做全局单击映射，双击、长按和分应用配置留到后续版本；厂商驱动已经改写成键盘事件或「无操作」的侧键不会出现在鼠标监听里。
- 平滑滚动只处理鼠标滚轮：触控板、Magic Mouse 和 ⌘+滚轮保持系统原生。与 iScroll / Mos / 罗技 Options 同时运行会双重平滑，需要先退出它们；部分鼠标驱动会把滚轮伪装成带相位的连续事件，这类事件会被当作触控板放行。
- 热键翻译需要自备 OpenAI Chat Completions 兼容供应商。API Key 保存在 `~/Library/Application Support/MacExpert/translation.key`（目录 0700、文件 0600，仅当前用户可读），不经过中转服务；应用日志不记录 Key 和输入文本。

## 与 TypeClip 的关系

原 [TypeClip](https://github.com/LuohaoSun/TypeClip) 的敲入引擎、键位映射、输入法处理与热键机制已完整并入本项目，TypeClip 仓库可退役。

日志位置从 `~/Library/Logs/TypeClip.log` 改为 `~/Library/Logs/MacExpert.log`；设置项因为 bundle id 不同会重新初始化一次。

## 许可证

[MIT](LICENSE)

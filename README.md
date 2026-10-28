# MacExpert

自用的 macOS 菜单栏小工具集。菜单栏菜单负责快速敲入，完整功能与设置都放在主窗口里，多个小功能用侧边栏切换。

## 功能

| 功能 | 说明 | 状态 |
| --- | --- | --- |
| 敲入 | 把剪贴板文本逐键敲入当前应用（原 TypeClip） | 可用 |
| 映射 | 鼠标侧键/中键 → 键盘组合键 | 界面原型 |
| 翻译 | 选中文本 → 热键 → 译文浮层 | 界面原型 |

菜单栏原生菜单只保留高频动作：权限状态、剪贴板摘要、敲入/中断、主窗口入口。敲入速度、输入法、开机自启、诊断日志等配置都在主窗口里，不再挤在菜单栏下拉菜单中。

主窗口打开时会临时显示 Dock 图标和 App 菜单；关闭窗口后回到纯菜单栏状态，不占用 Dock。

「敲入」完整继承了 TypeClip 的能力：

- **键码优先注入 + Unicode 回退**：先用 `UCKeyTranslate` 按当前键盘布局反查键码、真实地合成按键事件；布局敲不出的字符（汉字/emoji）回退 Unicode 注入。`#`、`@` 这类 Shift 符号在堡垒机里不会退化成裸数字。
- **修饰键加固**：连续同修饰字符整段按住 Shift；修饰键延迟保底 100ms；发字符前按 `flagsState` 自愈补发，适应远程端登记修饰状态慢的问题。
- 两个可调维度：**敲入速度**（字符间隔、按住时长、随机抖动、修饰键延迟都由它派生）与 **输入法** 三态（不动 / 切英文 / 切英文并恢复）。
- 敲入过程中再按一次热键 = 中断。
- 开机自启、剪贴板预览、进度显示、诊断日志。

## 安装

要求：macOS 15+，Apple 芯片。

1. 从 [Releases](https://github.com/LuohaoSun/MacExpert/releases) 下载最新的 DMG（文件名形如 `MacExpert-<版本>.dmg`，以 Releases 页面上的版本为准）。
2. 打开 DMG，把 `MacExpert.app` 拖进「应用程序」。
3. 首次打开请右键 →「打开」（本包未公证，直接双击会被 Gatekeeper 拦下）。
4. 授权：系统设置 → 隐私与安全性 → 辅助功能 → 开启 MacExpert。菜单栏菜单里会出现「去授权…」；也可以选「打开主窗口」，在窗口里的权限卡片处理。
5. 日常配置：从菜单栏菜单里选「打开主窗口」，敲入速度、输入法、开机自启、诊断日志都在窗口里。主窗口打开时会出现 Dock 图标和 App 菜单，关闭后回到菜单栏常驻。
6. 复制文本 → 切到目标窗口（远程桌面 / 堡垒机 / 虚拟机）→ 按 **⌃⌘V** 敲入；按 **⌃⌘↩** 敲入并在结尾补一个回车。
7. 敲入过程中再按一次 **⌃⌘V** 或 **⌃⌘↩** 可中断。

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
│   └── TypeClip/
│       ├── TyperEngine.swift        # 时间表驱动的逐键注入引擎
│       ├── Keymap.swift             # 当前键盘布局 → 键码反查、输入法切换
│       ├── TypeClipFeature.swift    # 功能状态、速度派生、剪贴板摘要
│       ├── TypeClipFeature+Module.swift # 实现 FeatureModule、注册热键
│       └── TypeClipPhase+UI.swift   # 敲入状态 → 界面文案/颜色
├── UI/
│   ├── Theme.swift                 # 设计令牌与卡片/键帽/徽章等零件
│   ├── MenuBarMenu.swift           # 菜单栏原生菜单：状态、剪贴板摘要、敲入、主窗口
│   ├── MainWindowController.swift  # 主窗口入口
│   ├── WindowActivator.swift       # 窗口激活策略：Dock/App 菜单
│   ├── NativeSidebarSplit.swift    # EZS 同款原生 NSSplitViewController 侧栏
│   ├── MainWindowView.swift        # 主窗口 + 侧栏 + 功能路由
│   ├── PageComponents.swift        # 功能页共用的分区/卡片组件
│   ├── TypeClipView.swift          # 敲入功能页
│   ├── PlaceholderViews.swift      # 映射 / 翻译界面原型
│   └── SettingsView.swift          # 权限、开机自启、日志、关于
└── Dev/
    └── PreviewRenderer.swift # 仅 dev：跟着 Feature.allCases 渲染各页 PNG

Tests/
├── UnitTests.swift   # 纯逻辑单测（清洗、速度派生、功能注册表）
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
- 按键映射与热键翻译目前只有界面原型，尚未接入实际逻辑。

## 与 TypeClip 的关系

原 [TypeClip](https://github.com/LuohaoSun/TypeClip) 的敲入引擎、键位映射、输入法处理与热键机制已完整并入本项目，TypeClip 仓库可退役。

日志位置从 `~/Library/Logs/TypeClip.log` 改为 `~/Library/Logs/MacExpert.log`；设置项因为 bundle id 不同会重新初始化一次。

## 许可证

[MIT](LICENSE)

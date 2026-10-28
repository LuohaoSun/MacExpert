# MacExpert

自用的 macOS 菜单栏小工具集。一个常驻菜单栏的 App，用顶部页签装多个互不打扰的小功能。

## 功能

| 页签 | 功能 | 状态 |
| --- | --- | --- |
| 敲入 | 把剪贴板文本逐键敲入当前应用（原 TypeClip） | 可用 |
| 映射 | 鼠标侧键/中键 → 键盘组合键 | 界面原型 |
| 翻译 | 选中文本 → 热键 → 译文浮层 | 界面原型 |

「敲入」完整继承了 TypeClip 的能力：

- **键码优先注入 + Unicode 回退**：先用 `UCKeyTranslate` 按当前键盘布局反查键码、真实地合成按键事件；布局敲不出的字符（汉字/emoji）回退 Unicode 注入。`#`、`@` 这类 Shift 符号在堡垒机里不会退化成裸数字。
- **修饰键加固**：连续同修饰字符整段按住 Shift；修饰键延迟保底 100ms；发字符前按 `flagsState` 自愈补发，适应远程端登记修饰状态慢的问题。
- 两个可调维度：**敲入速度**（字符间隔、按住时长、随机抖动、修饰键延迟都由它派生）与 **输入法** 三态（不动 / 切英文 / 切英文并恢复）。
- 敲入过程中再按一次热键 = 中断。
- 开机自启、剪贴板预览、进度显示、诊断日志。

## 安装

要求：macOS 13+，Apple 芯片。

1. 从 [Releases](https://github.com/LuohaoSun/MacExpert/releases) 下载最新的 `MacExpert-0.1.0.dmg`。
2. 打开 DMG，把 `MacExpert.app` 拖进「应用程序」。
3. 首次打开请右键 →「打开」（本包 adhoc 签名、未公证，直接双击会被 Gatekeeper 拦下）。
4. 授权：系统设置 → 隐私与安全性 → 辅助功能 → 开启 MacExpert。菜单栏面板顶部会有橙色提醒，点「去授权」可直达。
5. 复制文本 → 切到目标窗口（远程桌面 / 堡垒机 / 虚拟机）→ 按 **⌃⌘V** 敲入；按 **⌃⌘↩** 敲入并在结尾补一个回车。
6. 敲入过程中再按一次 **⌃⌘V** 或 **⌃⌘↩** 可中断。

## 从源码构建

只需要 Xcode Command Line Tools，不需要完整 Xcode：

```sh
./build.sh dev       # 开发构建：含 dev 钩子，仅本机调试用
./build.sh release   # 发布构建：编掉全部 dev 钩子
./make-dmg.sh        # 打一个带拖拽安装引导的 DMG（自动先做 release 构建）
```

开发构建的额外入口：

```sh
# 把四个页签在浅色/深色下渲染成 PNG，检查布局
build/MacExpert.app/Contents/MacOS/MacExpert --preview build/preview

# 检查辅助功能权限、键位表大小、文本清洗
build/MacExpert.app/Contents/MacOS/MacExpert --selfcheck

# 经分布式通知驱动一次敲入（需要常驻实例，等价于按热键）
build/MacExpert.app/Contents/MacOS/MacExpert --notify-drive

# 冒烟测试：验证中英文 / Shift 符号 / 换行能完整敲进另一个应用
# 会短暂打开测试窗口并覆盖剪贴板，需要终端已有辅助功能权限
./Tests/smoke.sh
```

> `--notify-drive` 没有来源校验：本机任何进程都能借此让常驻实例替它敲键盘，等于借用 MacExpert 的 TCC 授权。因此它只在 dev 构建里存在，`release` 构建会校验二进制中无钩子残留。

## 目录结构

```
Sources/
├── MacExpertApp.swift        # @main、菜单栏入口、全局热键注册、dev 钩子
├── Core/
│   ├── AppState.swift        # 功能注册表、全局状态、权限
│   ├── HotkeyCenter.swift    # Carbon 全局热键
│   └── AppLog.swift          # ~/Library/Logs/MacExpert.log（0600）
├── Features/
│   └── TypeClip/
│       ├── TyperEngine.swift # 时间表驱动的逐键注入引擎
│       ├── Keymap.swift      # 当前键盘布局 → 键码反查、输入法切换
│       └── TypeClipFeature.swift
├── UI/
│   ├── Theme.swift           # 设计令牌与卡片/键帽/徽章等零件
│   ├── RootPanel.swift       # 菜单栏面板外壳、页签、权限横幅、底栏
│   ├── TypeClipView.swift    # 敲入功能页
│   ├── PlaceholderViews.swift# 映射 / 翻译界面原型
│   └── SettingsView.swift    # 权限、开机自启、日志、关于
└── Dev/
    └── PreviewRenderer.swift # 仅 dev：把面板渲染成 PNG

Tests/
├── TypeTarget.swift          # 冒烟测试的接收窗口
└── smoke.sh                  # 端到端敲入测试
```

新增功能时：在 `Feature` 里加一个 case，在 `RootPanel` 的路由里接上视图，再按需在 `AppDelegate` 注册热键。

## 已知限制

- 仅构建 arm64 slice（Apple 芯片）。
- adhoc 签名、未公证：他人首次打开需要右键「打开」；替换安装后需要在「辅助功能」里重新授权。
- 如果远程端完全拦截合成键盘事件，MacExpert 无法绕过（那是目标系统的主动防护）。
- 按键映射与热键翻译目前只有界面原型，尚未接入实际逻辑。

## 与 TypeClip 的关系

原 [TypeClip](https://github.com/LuohaoSun/TypeClip) 的敲入引擎、键位映射、输入法处理与热键机制已完整并入本项目，TypeClip 仓库可退役。

日志位置从 `~/Library/Logs/TypeClip.log` 改为 `~/Library/Logs/MacExpert.log`；设置项因为 bundle id 不同会重新初始化一次。

## 许可证

[MIT](LICENSE)

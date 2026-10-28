import AppKit
import ApplicationServices
import Combine
import ServiceManagement

// MARK: - 功能注册表

/// 一个功能模块。新增功能时在这里加一个 case，
/// 再在 `MainWindowView` 的路由里接上对应视图即可。
enum Feature: String, CaseIterable, Identifiable, Hashable {
    case typeClip
    case keyMapping
    case translate

    var id: String { rawValue }

    /// 页面标题。
    var title: String {
        switch self {
        case .typeClip: return "剪贴板敲入"
        case .keyMapping: return "按键映射"
        case .translate: return "热键翻译"
        }
    }

    var subtitle: String {
        switch self {
        case .typeClip: return "TypeClip · 逐键敲入"
        case .keyMapping: return "鼠标按键 → 键盘组合键"
        case .translate: return "选中文本 → 译文"
        }
    }

    var icon: String {
        switch self {
        case .typeClip: return "keyboard"
        case .keyMapping: return "computermouse"
        case .translate: return "character.bubble"
        }
    }

    /// 当前版本是否已经能用：注册表里有模块就算可用。
    /// 未上线的功能只展示界面原型。
    var isAvailable: Bool { FeatureRegistry.module(for: self) != nil }
}

// MARK: - 主窗口路由

enum MainSection: Hashable, Identifiable {
    case feature(Feature)
    case settings

    var id: String {
        switch self {
        case .feature(let feature): return feature.rawValue
        case .settings: return "settings"
        }
    }

    var feature: Feature? {
        if case .feature(let feature) = self { return feature }
        return nil
    }

    var title: String {
        switch self {
        case .feature(let feature): return feature.title
        case .settings: return "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .feature(let feature): return feature.subtitle
        case .settings: return "权限、通用、日志与关于"
        }
    }

    var icon: String {
        switch self {
        case .feature(let feature): return feature.icon
        case .settings: return "gearshape"
        }
    }

    var badge: String? {
        switch self {
        case .feature(let feature): return feature.isAvailable ? nil : "规划中"
        case .settings: return nil
        }
    }

    var isAvailable: Bool {
        switch self {
        case .feature(let feature): return feature.isAvailable
        case .settings: return true
        }
    }
}

// MARK: - 全局应用状态

final class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard

    let typeClip = TypeClipFeature.shared

    /// 主窗口当前页。菜单栏面板不参与这个路由，只负责快速敲入。
    @Published var section: MainSection {
        didSet { defaults.set(section.id, forKey: "mainSection") }
    }

    @Published var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") }
    }

    @Published var trusted: Bool = AXIsProcessTrusted()
    @Published var loginEnabled: Bool = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    /// app 每次重新激活时的统一刷新入口（Combine 订阅，常驻）。
    private var activationObserver: AnyCancellable?

    init() {
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true

        // 从 0.1.0 的 selectedFeature 迁移到新的 mainSection。
        let raw = defaults.string(forKey: "mainSection")
            ?? defaults.string(forKey: "selectedFeature")
            ?? ""
        if raw == "settings" {
            section = .settings
        } else if let feature = Feature(rawValue: raw) {
            section = .feature(feature)
        } else {
            section = .feature(.typeClip)
        }

        // 窗口重新成为焦点时统一刷新权限和当前模块状态。
        activationObserver = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOnActivation() }
    }

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    func open(_ section: MainSection) {
        self.section = section
        FeatureRegistry.onOpened(section)
    }

    /// app 被激活时的统一刷新：权限 + 当前模块自己的刷新。
    func refreshOnActivation() {
        guard !RuntimeFlags.isRenderingPreview else { return }
        refreshTrust()
        FeatureRegistry.onActivated(section)
    }

    func openSettings() {
        open(.settings)
    }

    func refreshTrust() {
        let now = AXIsProcessTrusted()
        if trusted != now { trusted = now }
    }

    func markUntrusted() {
        if trusted { trusted = false }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginEnabled = enabled
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = "开机自启设置失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 运行时开关

enum RuntimeFlags {
    /// 仅 dev 预览使用：让视图在离屏渲染时跳过权限/剪贴板刷新。
    static var isRenderingPreview = false
    /// 仅 dev 诊断使用：打开窗口但不切换激活策略、不抢焦点。
    static var suppressWindowActivation = false
}

// MARK: - 权限

enum Permissions {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 同时做两件事：打开系统设置的辅助功能页，并触发系统自带的授权提示。
    static func requestAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

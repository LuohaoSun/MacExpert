import AppKit
import ApplicationServices
import Combine
import ServiceManagement

// MARK: - 功能注册表

/// 菜单栏面板里的功能页签。新增功能时在这里加一个 case，
/// 再在 `RootPanel` 的路由里接上对应视图即可。
enum Feature: String, CaseIterable, Identifiable, Hashable {
    case typeClip
    case keyMapping
    case translate

    var id: String { rawValue }

    /// 页签上的短标题。
    var tabTitle: String {
        switch self {
        case .typeClip: return "敲入"
        case .keyMapping: return "映射"
        case .translate: return "翻译"
        }
    }

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

    /// 当前版本是否已经能用。未上线的功能只展示界面原型。
    var isAvailable: Bool { self == .typeClip }
}

// MARK: - 全局应用状态

final class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard

    let typeClip = TypeClipFeature.shared

    @Published var selectedFeature: Feature {
        didSet { defaults.set(selectedFeature.rawValue, forKey: "selectedFeature") }
    }

    /// true 时面板显示设置页，页签全部处于未选中态。
    @Published var showingSettings = false
    @Published var trusted: Bool = AXIsProcessTrusted()
    @Published var loginEnabled: Bool = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    init() {
        let raw = defaults.string(forKey: "selectedFeature") ?? ""
        selectedFeature = Feature(rawValue: raw) ?? .typeClip
    }

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func open(_ feature: Feature) {
        showingSettings = false
        selectedFeature = feature
        if feature == .typeClip { typeClip.refreshPasteboard() }
    }

    func toggleSettings() {
        showingSettings.toggle()
        if showingSettings { refreshTrust() }
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
    /// 仅 dev 预览使用：让 RootPanel 在离屏渲染时展开 ScrollView 内的全部内容。
    static var isRenderingPreview = false
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

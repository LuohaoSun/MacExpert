import Foundation

// MARK: - 功能模块

/// 一个可安装的功能模块。功能自己的状态、热键和生命周期都由实现方负责，
/// 主窗口和菜单栏只通过这个协议与模块打交道。
protocol FeatureModule: AnyObject {
    var feature: Feature { get }
    var statusLine: String? { get }
    func install()
    func onOpened()
    func onActivated()
    func prepareForTermination()
}

extension FeatureModule {
    var statusLine: String? { nil }
    func onOpened() {}
    func onActivated() {}
    func prepareForTermination() {}
}

// MARK: - 模块注册表

/// 全应用唯一的模块清单。新增功能时在 `modules` 里加一行即可，
/// 安装、激活、状态行和可用性判断都会自动跟着走。
enum FeatureRegistry {

    static let modules: [FeatureModule] = [
        TypeClipFeature.shared,
    ]

    static func module(for feature: Feature) -> FeatureModule? {
        modules.first { $0.feature == feature }
    }

    /// 已注册模块 = 当前版本可用；未注册的只展示界面原型。
    static func isAvailable(_ feature: Feature) -> Bool {
        module(for: feature) != nil
    }

    static func installAll() {
        for module in modules { module.install() }
    }

    /// 菜单栏状态行：第一个有内容的模块优先。
    static func statusLine() -> String? {
        for module in modules {
            if let line = module.statusLine { return line }
        }
        return nil
    }

    static func onOpened(_ section: MainSection) {
        guard let feature = section.feature else { return }
        module(for: feature)?.onOpened()
    }

    static func onActivated(_ section: MainSection) {
        guard let feature = section.feature else { return }
        module(for: feature)?.onActivated()
    }

    static func prepareForTermination() {
        for module in modules { module.prepareForTermination() }
    }
}

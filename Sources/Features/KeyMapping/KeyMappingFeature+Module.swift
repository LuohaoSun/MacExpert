import AppKit
import Foundation

// MARK: - FeatureModule 接入

extension KeyMappingFeature: FeatureModule {

    var feature: Feature { .keyMapping }

    var statusLine: String? {
        guard enabled, hasActiveMappings else { return nil }

        switch tapState {
        case .permissionDenied:
            return "鼠标按键映射需要辅助功能权限"
        case .failed(let message):
            return "鼠标按键映射未启动：\(message)"
        case .stopped:
            return "鼠标按键映射未启动"
        case .running:
            return nil
        }
    }

    func install() {
        start()
    }

    func onOpened() {
        refreshPermission()
    }

    func onActivated() {
        refreshPermission()
    }

    func prepareForTermination() {
        shutdown()
    }
}

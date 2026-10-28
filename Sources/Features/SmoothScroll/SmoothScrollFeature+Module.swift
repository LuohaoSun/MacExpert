import Foundation

// MARK: - FeatureModule 接入

extension SmoothScrollFeature: FeatureModule {

    var feature: Feature { .smoothScroll }

    var statusLine: String? {
        guard enabled else { return nil }

        switch tapState {
        case .permissionDenied:
            return "平滑滚动需要辅助功能权限"
        case .failed(let message):
            return "平滑滚动未启动：\(message)"
        case .stopped:
            return "平滑滚动未启动"
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

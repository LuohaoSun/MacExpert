import Foundation

// MARK: - FeatureModule 接入

extension MonitorFeature: FeatureModule {

    var feature: Feature { .monitor }

    func onOpened() {
        refreshNow()
    }

    func onActivated() {
        refreshNow()
    }

    func prepareForTermination() {
        shutdown()
    }
}

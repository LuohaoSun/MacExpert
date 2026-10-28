import SwiftUI

/// 敲入阶段在界面上的文字与颜色。
extension TypeClipFeature.Phase {
    var label: String {
        switch self {
        case .idle: return "就绪"
        case .typing: return "敲入中"
        case .done: return "完成"
        case .aborted: return "已中断"
        case .failed: return "异常"
        }
    }

    var color: Color {
        switch self {
        case .idle: return Theme.accent
        case .typing: return .orange
        case .done: return Theme.green
        case .aborted: return Color.gray
        case .failed: return .red
        }
    }
}

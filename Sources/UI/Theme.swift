import SwiftUI

// MARK: - 设计令牌

enum Theme {
    static let panelWidth: CGFloat = 388
    static let contentHeight: CGFloat = 520
    static let cardRadius: CGFloat = 12

    static let accent = Color(red: 0.30, green: 0.48, blue: 0.97)
    static let teal = Color(red: 0.14, green: 0.68, blue: 0.62)
    static let green = Color(red: 0.16, green: 0.64, blue: 0.46)
    static let purple = Color(red: 0.55, green: 0.42, blue: 0.95)

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.38, green: 0.56, blue: 1.0), Color(red: 0.12, green: 0.72, blue: 0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 卡片

struct PanelCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.065), lineWidth: 1)
            )
    }
}

struct CardTitle: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 小零件

struct IconTile: View {
    let systemName: String
    var color: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(color.opacity(0.13))
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .foregroundStyle(filled ? Color.white : color)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.13))
            )
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

struct KeyCap: View {
    let text: String
    var onFilled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(onFilled ? Color.white : Color.primary)
            .frame(minWidth: 19, minHeight: 19)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onFilled ? Color.white.opacity(0.18) : Color.primary.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        onFilled ? Color.white.opacity(0.25) : Color.primary.opacity(0.09),
                        lineWidth: 0.8
                    )
            )
    }
}

struct HotkeyCaps: View {
    let caps: [String]
    var onFilled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(caps.indices, id: \.self) { index in
                KeyCap(text: caps[index], onFilled: onFilled)
            }
        }
    }
}

/// 主操作按钮：自绘实心样式，不依赖窗口是否处于 key 状态，
/// 避免 borderedProminent 在菜单栏面板里偶发落成灰白外观。
struct FilledActionButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(configuration.isPressed ? color.opacity(0.85) : color)
            )
            .shadow(color: color.opacity(0.24), radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SettingSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = "ms"
    var step: Double = 10

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .frame(width: 62, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: { value = (($0 / step).rounded() * step) }
                ),
                in: range
            )
            .controlSize(.small)
            Text("\(Int(value))\(unit)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

/// 页内小标题 + 右侧说明，用于「规划中」的提示行。
struct InlineNote: View {
    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

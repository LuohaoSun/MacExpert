import AppKit
import SwiftUI

// MARK: - 设计令牌

enum Theme {
    static let accent = Color(red: 0.30, green: 0.48, blue: 0.97)
    static let green = Color(red: 0.16, green: 0.64, blue: 0.46)
}

// MARK: - 卡片

/// 内容卡片：EZS 同款白底页 + 细描边卡片；状态卡可换浅灰底做层级。
struct CardSurface<Content: View>: View {
    let content: Content
    var fill: Color
    var borderOpacity: Double

    init(
        fill: Color = Color(nsColor: .controlBackgroundColor),
        borderOpacity: Double = 0.10,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.borderOpacity = borderOpacity
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: 1)
        )
    }
}

// MARK: - 小零件

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

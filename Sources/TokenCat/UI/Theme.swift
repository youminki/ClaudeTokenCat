import SwiftUI

/// 팝오버 디자인 토큰. 색은 상태를 알릴 때만 쓰고, 나머지는 흰색의 농도와 글자 크기로 위계를 만든다.
enum Theme {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.09)
    static let track = Color.white.opacity(0.11)
    static let hover = Color.white.opacity(0.08)

    static let normal = Color(white: 0.88)
    static let warning = Color(red: 0.94, green: 0.66, blue: 0.27)
    static let critical = Color(red: 0.93, green: 0.36, blue: 0.32)
    static let positive = Color(red: 0.40, green: 0.78, blue: 0.50)

    /// 사용률 단계 색. 80% 전까지는 색을 쓰지 않는다.
    static func level(_ percent: Double) -> Color {
        switch percent {
        case ..<80: return normal
        case ..<95: return warning
        default: return critical
        }
    }

    /// 섹션 이름 (세션, 주간, 속도…).
    static let label = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 11)
    static let value = Font.system(size: 13, weight: .medium).monospacedDigit()
}

/// 구획선.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// 큰 숫자 + 작은 단위 (예: 42 %).
struct Figure: View {
    let value: String
    let unit: String
    var color: Color = Theme.primary
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .tracking(-0.6)
            Text(unit)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(color.opacity(0.7))
        }
        .foregroundStyle(color)
    }
}

/// 팝오버 아래 도구 막대의 아이콘 버튼. 배경 없이 두고 올렸을 때만 옅은 바탕을 깐다.
struct ToolbarButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary

    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(configuration: configuration, tint: tint)
    }

    private struct ToolbarButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @StateObject private var hover = HoverFlag()

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(hover.on ? tint : Theme.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(configuration.isPressed ? Color.white.opacity(0.14) : (hover.on ? Theme.hover : .clear))
                )
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

/// macOS 27 SDK의 `@State`는 매크로라 Command Line Tools만으로는 빌드되지 않는다.
/// install.sh가 Xcode 없이도 돌도록 뷰 상태를 ObservableObject로 둔다.
final class HoverFlag: ObservableObject {
    @Published var on = false
}

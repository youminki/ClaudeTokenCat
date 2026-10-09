import SwiftUI
import UsageCore

/// 팝오버 디자인 토큰. 색은 상태를 알릴 때만 쓰고, 나머지는 흰색의 농도와 글자 크기로 위계를 만든다.
enum Theme {
    static let primary = Color.white.opacity(0.92)
    // 어두운 카드 위에서도 작은 글씨가 읽히는 농도 (보조 글자 대비 약 4.5:1)
    static let secondary = Color.white.opacity(0.68)
    static let tertiary = Color.white.opacity(0.5)
    static let hairline = Color.white.opacity(0.09)
    static let track = Color.white.opacity(0.11)
    static let hover = Color.white.opacity(0.08)
    /// 카드 바탕. 구획선 대신 옅은 면으로 묶어 숫자가 먼저 읽히게 한다.
    static let surface = Color.white.opacity(0.045)

    // 팝오버는 늘 다크라 iOS 다크 모드 시스템 색을 그대로 쓴다
    static let accent = Color(nsColor: NSColor(hex: 0x0A84FF))
    static let warning = Color(nsColor: NSColor(hex: 0xFF9F0A))
    static let critical = Color(nsColor: NSColor(hex: 0xFF453A))
    static let positive = Color(nsColor: NSColor(hex: 0x30D158))

    /// 사용률 링 색: 80% 전 파랑, 80% 주황, 95% 빨강.
    static func ring(_ percent: Double) -> Color {
        switch percent {
        case ..<80: return accent
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

/// 정보 묶음 카드.
struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// 시간 대비 사용 속도 배지 (여유·적정·빠름·한도 임박).
struct PaceBadge: View {
    let pace: GaugeMath.Pace

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var title: String {
        switch pace {
        case .relaxed: return "여유"
        case .steady: return "적정"
        case .fast: return "빠름"
        case .critical: return "한도 임박"
        }
    }

    private var color: Color {
        switch pace {
        case .relaxed: return Theme.positive
        case .steady: return Theme.secondary
        case .fast: return Theme.warning
        case .critical: return Theme.critical
        }
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

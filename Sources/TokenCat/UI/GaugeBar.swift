import SwiftUI

/// 사용률 게이지 바. 0~60% 파랑 → 60~80% 노랑 → 80%+ 빨강 (§F3).
/// 공식 조회값(base) 위에 얹힌 보간분은 옅게 그려 실측과 추정을 구분한다.
struct GaugeBar: View {
    let percent: Double
    var basePercent: Double? = nil

    static func color(for percent: Double) -> Color {
        switch percent {
        case ..<60: return .blue
        case ..<80: return .yellow
        default: return .red
        }
    }

    private func width(_ percent: Double, in total: CGFloat) -> CGFloat {
        total * min(max(percent, 0), 100) / 100
    }

    var body: some View {
        let color = Self.color(for: percent)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color.opacity(basePercent == nil ? 1 : 0.45))
                    .frame(width: width(percent, in: geo.size.width))
                if let basePercent {
                    Capsule()
                        .fill(color)
                        .frame(width: width(basePercent, in: geo.size.width))
                }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: percent)
        .accessibilityElement()
        .accessibilityValue(Format.percent(percent))
    }
}

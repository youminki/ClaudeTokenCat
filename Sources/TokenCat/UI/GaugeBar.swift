import SwiftUI

/// 사용률 게이지 바. 0~60% 파랑 → 60~80% 노랑 → 80%+ 빨강 (§F3).
/// 공식 조회값(base) 위에 얹힌 보간분은 옅게 그려 실측과 추정을 구분한다.
struct GaugeBar: View {
    let percent: Double
    var basePercent: Double? = nil
    /// 창이 지난 비율(0~1). 세로선으로 그려 사용량이 시간보다 앞서는지 보이게 한다.
    var elapsed: Double? = nil

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
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                if let elapsed {
                    Capsule()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(width(elapsed * 100, in: geo.size.width) - 1, 0), geo.size.width - 2))
                }
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.3), value: percent)
        .help(elapsed.map { "세로선: 이번 창 시간의 \(Int(($0 * 100).rounded()))% 경과" } ?? "")
        .accessibilityElement()
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        guard let elapsed else { return Format.percent(percent) }
        return "\(Format.percent(percent)), 시간 \(Int((elapsed * 100).rounded()))% 경과"
    }
}

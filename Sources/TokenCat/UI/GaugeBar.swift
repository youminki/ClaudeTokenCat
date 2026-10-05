import SwiftUI

/// 사용률 게이지 바. 0~60% 파랑 → 60~80% 노랑 → 80%+ 빨강 (§F3).
struct GaugeBar: View {
    let fraction: Double   // 0.0 ~ 1.0+

    private var color: Color {
        switch fraction {
        case ..<0.6: return .blue
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

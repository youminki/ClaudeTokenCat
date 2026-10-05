import SwiftUI

/// 최근 30분 tokens/min 미니 그래프 (§F3). 마우스를 올린 분을 `hoverIndex`로 알린다.
struct Sparkline: View {
    let values: [Int]
    @Binding var hoverIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 0, 1)
            let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX,
                        y: geo.size.height * (1 - CGFloat(v) / CGFloat(maxValue)))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.05)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                if let i = hoverIndex, points.indices.contains(i) {
                    Path { p in
                        p.move(to: CGPoint(x: points[i].x, y: 0))
                        p.addLine(to: CGPoint(x: points[i].x, y: geo.size.height))
                    }
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .position(points[i])
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !values.isEmpty else { return }
                    let index = min(max(Int((location.x / stepX).rounded()), 0), values.count - 1)
                    if hoverIndex != index { hoverIndex = index }   // 같은 분이면 팝오버를 다시 그리지 않는다
                case .ended:
                    if hoverIndex != nil { hoverIndex = nil }
                }
            }
        }
        .frame(height: 24)
    }
}

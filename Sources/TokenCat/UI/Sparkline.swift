import SwiftUI

/// 최근 30분 tokens/min 미니 그래프 (§F3).
struct Sparkline: View {
    let values: [Int]

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
                .fill(Color.accentColor.opacity(0.2))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Color.accentColor, lineWidth: 1.2)
            }
        }
        .frame(height: 24)
    }
}

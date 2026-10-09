import SwiftUI

/// 사용률 링 (iOS 배터리·활동 위젯처럼). 가운데에 %를 크게, 링 위에 지난 시간 눈금을 둔다.
struct RingGauge: View {
    /// 공식 값이 없으면 nil. 링을 비우고 가운데에 "--".
    let percent: Double?
    /// 가운데 숫자. 다른 화면과 같은 반올림을 쓰도록 바깥에서 받는다.
    let label: String?
    /// 창이 지난 비율(0~1). 링 위 흰 눈금보다 색 링이 앞서면 시간보다 빨리 쓰는 중.
    var elapsed: Double?
    var lineWidth: CGFloat = 8
    /// 작은 링은 가운데 숫자를 빼고 옆에 따로 적는다.
    var showsLabel = true

    var body: some View {
        let value = min(max(percent ?? 0, 0), 100)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle().stroke(Theme.track, lineWidth: lineWidth)
                    .frame(width: side - lineWidth, height: side - lineWidth)
                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(Theme.ring(value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: side - lineWidth, height: side - lineWidth)
                if let elapsed, percent != nil {
                    let angle = elapsed * 2 * .pi - .pi / 2
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2.5, height: lineWidth + 5)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                }
                if showsLabel { HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(label ?? "--")
                        .font(.system(size: side * 0.27, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: side * 0.13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(percent == nil ? Theme.tertiary : Theme.primary)
                .position(center) }
            }
        }
        .animation(.easeOut(duration: 0.4), value: percent)
        .accessibilityElement()
        .accessibilityValue(label.map { "\($0)%" } ?? "값 없음")
    }
}

/// 분당 토큰 막대 (iOS 스크린 타임 차트처럼). 마우스를 올린 분을 `hoverIndex`로 알린다.
struct ActivityBars: View {
    let values: [Int]
    @Binding var hoverIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = 2
            let barWidth = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
            let peak = CGFloat(max(values.max() ?? 0, 1))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let height = value > 0 ? max(geo.size.height * CGFloat(value) / peak, 2) : 1
                    UnevenTopRoundedBar(radius: min(barWidth / 2, 2))
                        .fill(color(index: index, value: value))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !values.isEmpty else { return }
                    let index = min(max(Int(location.x / (barWidth + gap)), 0), values.count - 1)
                    if hoverIndex != index { hoverIndex = index }   // 같은 분이면 팝오버를 다시 그리지 않는다
                case .ended:
                    if hoverIndex != nil { hoverIndex = nil }
                }
            }
        }
        .frame(height: 46)
    }

    /// 가리킨 막대와 지금 분은 진하게, 나머지는 옅게. 쓰지 않은 분은 바닥 선만 남긴다.
    private func color(index: Int, value: Int) -> Color {
        guard value > 0 else { return Theme.track }
        if let hoverIndex { return Theme.accent.opacity(index == hoverIndex ? 1 : 0.35) }
        return Theme.accent.opacity(index == values.count - 1 ? 1 : 0.6)
    }
}

/// 위쪽 두 모서리만 둥근 막대.
private struct UnevenTopRoundedBar: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 카드 아래 수치 한 칸 (Stats·iStat Menus 팝업의 요약 칸처럼): 작은 이름 위에 큰 숫자.
struct StatColumn: View {
    let label: String
    let value: String
    var unit: String = ""

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

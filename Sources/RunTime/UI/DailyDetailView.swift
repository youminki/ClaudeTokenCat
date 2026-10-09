import SwiftUI
import UsageCore

/// 일별 사용량 (iOS 스크린 타임처럼): 하루 평균을 크게, 그 아래 날짜별 막대와 평균선, 맨 아래 날짜별 목록.
/// 최근 8일, 이 Mac의 Claude Code 기록 기준.
struct DailyDetailView: View {
    @ObservedObject var engine: UsageEngine
    @StateObject private var hover = HoveredDay()

    var body: some View {
        let totals = engine.snapshot?.dailyTotals ?? []
        VStack(alignment: .leading, spacing: 18) {
            if totals.isEmpty {
                Text("아직 기록이 없습니다.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                summary(totals)
                chart(totals)
                GroupedSection("날짜별", footer: "비용은 API 단가로 환산한 참고값입니다.") {
                    ForEach(totals, id: \.dayStart) { row($0) }
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Palette.groupedBackground)
    }

    // MARK: 요약

    private func summary(_ totals: [UsageStore.DailyTotal]) -> some View {
        let total = totals.map(\.tokens).reduce(0, +)
        let cost = totals.map(\.costUSD).reduce(0, +)
        return VStack(alignment: .leading, spacing: 2) {
            Text("쓴 날 평균").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.tokens(total / totals.count))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Text("토큰").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text("최근 8일 중 쓴 날 \(totals.count)일 · 합계 \(Format.tokens(total)) 토큰 · 약 \(Format.usd(cost))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: 막대

    private func chart(_ totals: [UsageStore.DailyTotal]) -> some View {
        let days = totals.sorted { $0.dayStart < $1.dayStart }
        let peak = CGFloat(max(days.map(\.tokens).max() ?? 1, 1))
        let average = CGFloat(days.map(\.tokens).reduce(0, +)) / CGFloat(max(days.count, 1))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let index = hover.index, days.indices.contains(index) {
                    let day = days[index]
                    Text(dayTitle(day.dayStart)).font(.system(size: 12, weight: .semibold))
                    Text("\(Format.tokens(day.tokens)) · \(Format.usd(day.costUSD))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("날짜별 토큰").font(.system(size: 12, weight: .semibold))
                }
                Spacer()
            }
            .frame(height: 16)
            GeometryReader { geo in
                let height = geo.size.height
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(days.enumerated()), id: \.element.dayStart) { index, day in
                            stackedBar(day, height: max(height * CGFloat(day.tokens) / peak, 3))
                                .opacity(hover.index == nil || hover.index == index ? 1 : 0.4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .contentShape(Rectangle())   // 낮은 막대도 칸 전체에서 가리킬 수 있게
                                .onHover { hover.update(index, $0) }
                        }
                    }
                    // 평균선
                    let y = height * (1 - average / peak)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Palette.green, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("평균")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.green)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Palette.groupedRow))
                        .position(x: geo.size.width - 12, y: max(y - 8, 6))
                }
            }
            .frame(height: 120)
            HStack(spacing: 10) {
                ForEach(days, id: \.dayStart) { day in
                    Text(weekday(day.dayStart))
                        .font(.system(size: 10, weight: isToday(day.dayStart) ? .bold : .regular))
                        .foregroundStyle(isToday(day.dayStart) ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            legend(families(in: days))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.groupedRow))
    }

    /// 모델 계열별로 아래부터 쌓는다.
    private func stackedBar(_ day: UsageStore.DailyTotal, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(segments(of: day).reversed(), id: \.family) { segment in
                Rectangle()
                    .fill(Self.color(for: segment.family))
                    .frame(height: height * CGFloat(segment.tokens) / CGFloat(max(day.tokens, 1)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help(breakdown(day))
    }

    private func legend(_ families: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(families, id: \.self) { family in
                HStack(spacing: 4) {
                    Circle().fill(Self.color(for: family)).frame(width: 7, height: 7)
                    Text(family)
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }

    // MARK: 목록

    private func row(_ day: UsageStore.DailyTotal) -> some View {
        GroupedRow(dayTitle(day.dayStart)) {
            HStack(spacing: 10) {
                Text(Format.tokens(day.tokens)).monospacedDigit()
                Text(Format.usd(day.costUSD)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .font(.system(size: 13, weight: isToday(day.dayStart) ? .semibold : .regular))
        }
        .help(breakdown(day))
    }

    // MARK: 날짜

    private func isToday(_ date: Date) -> Bool { Calendar.current.isDateInToday(date) }

    private func dayTitle(_ date: Date) -> String {
        isToday(date) ? "오늘" : Self.dayFormatter.string(from: date)
    }

    private func weekday(_ date: Date) -> String {
        isToday(date) ? "오늘" : Self.weekdayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f
    }()

    // MARK: 모델 계열

    private struct Segment {
        let family: String
        let tokens: Int
    }

    private static let familyOrder = ["Fable", "Opus", "Sonnet", "Haiku"]

    private func segments(of day: UsageStore.DailyTotal) -> [Segment] {
        var byFamily: [String: Int] = [:]
        for (model, tokens) in day.modelTokens { byFamily[Self.family(of: model), default: 0] += tokens }
        return byFamily.map { Segment(family: $0.key, tokens: $0.value) }
            .sorted { Self.rank($0.family) < Self.rank($1.family) }
    }

    private func families(in totals: [UsageStore.DailyTotal]) -> [String] {
        Set(totals.flatMap { $0.modelTokens.keys.map(Self.family(of:)) })
            .sorted { Self.rank($0) < Self.rank($1) }
    }

    private func breakdown(_ day: UsageStore.DailyTotal) -> String {
        segments(of: day)
            .map { "\($0.family) \(Format.tokens($0.tokens))" }
            .joined(separator: " · ")
    }

    /// Opus·Sonnet·Haiku·Fable 밖의 모델은 "기타"로 묶는다.
    private static func family(of model: String) -> String {
        let name = Format.modelName(model)
        return familyOrder.contains(name) ? name : "기타"
    }

    private static func rank(_ family: String) -> Int {
        familyOrder.firstIndex(of: family) ?? familyOrder.count
    }

    private static func color(for family: String) -> Color {
        switch family {
        case "Fable": return Palette.orange
        case "Opus": return Palette.indigo
        case "Sonnet": return Palette.blue
        case "Haiku": return Palette.teal
        default: return Palette.gray
        }
    }
}

/// 마우스를 올린 날. `@State`를 못 쓰는 이유는 HoverFlag 참고.
final class HoveredDay: ObservableObject {
    @Published var index: Int?

    func update(_ index: Int, _ inside: Bool) {
        if inside { self.index = index } else if self.index == index { self.index = nil }
    }
}

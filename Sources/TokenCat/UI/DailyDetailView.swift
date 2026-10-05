import SwiftUI
import UsageCore

/// 📊 일별 사용 내역 (v1.1 — 최근 8일, JSONL 집계 기준).
struct DailyDetailView: View {
    @ObservedObject var engine: UsageEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("일별 사용 내역").font(.headline)
            Text("로컬 JSONL 집계 (Claude Code분, 최근 8일) · 비용은 API 단가 환산 추정")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let totals = engine.snapshot?.dailyTotals ?? []
            if totals.isEmpty {
                Text("데이터 없음").foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                legend(families(in: totals))
                table(totals)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func table(_ totals: [UsageStore.DailyTotal]) -> some View {
        let peak = max(totals.map(\.tokens).max() ?? 1, 1)
        let today = Calendar.current.startOfDay(for: Date())
        let totalTokens = totals.map(\.tokens).reduce(0, +)
        let totalCost = totals.map(\.costUSD).reduce(0, +)

        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("날짜")
                Text("")
                Text("토큰").gridColumnAlignment(.trailing)
                Text("비용(추정)").gridColumnAlignment(.trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(totals, id: \.dayStart) { day in
                let isToday = day.dayStart == today
                GridRow {
                    Text(isToday ? "오늘" : Self.dayFormatter.string(from: day.dayStart))
                    stackedBar(day, peak: peak)
                    Text(Format.tokens(day.tokens)).monospacedDigit()
                    Text(Format.usd(day.costUSD)).monospacedDigit()
                }
                .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                .help(breakdown(day))
            }
            Divider()
            GridRow {
                Text("합계")
                Text("활동일 평균 \(Format.usd(totalCost / Double(totals.count)))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(Format.tokens(totalTokens)).monospacedDigit()
                Text(Format.usd(totalCost)).monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    /// 하루 막대를 모델 계열별 길이로 나눠 칠한다. 막대 전체 길이는 기간 최대값 대비 비율.
    private func stackedBar(_ day: UsageStore.DailyTotal, peak: Int) -> some View {
        let segments = segments(of: day)
        return GeometryReader { geo in
            let full = max(geo.size.width * CGFloat(day.tokens) / CGFloat(peak), 2)
            HStack(spacing: 0) {
                ForEach(segments, id: \.family) { segment in
                    Rectangle()
                        .fill(Self.color(for: segment.family))
                        .frame(width: full * CGFloat(segment.tokens) / CGFloat(max(day.tokens, 1)))
                }
            }
            .frame(width: full, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(width: 100, height: 6)
    }

    private func legend(_ families: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(families, id: \.self) { family in
                HStack(spacing: 4) {
                    Circle().fill(Self.color(for: family)).frame(width: 7, height: 7)
                    Text(family)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

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
        case "Fable": return .orange
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .teal
        default: return .gray
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (E)"
        return f
    }()
}

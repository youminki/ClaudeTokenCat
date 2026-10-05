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
                table(totals)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func table(_ totals: [UsageStore.DailyTotal]) -> some View {
        let peak = max(totals.map(\.tokens).max() ?? 1, 1)
        let today = Calendar.current.startOfDay(for: Date())

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
                    bar(fraction: Double(day.tokens) / Double(peak), highlighted: isToday)
                    Text(Format.tokens(day.tokens)).monospacedDigit()
                    Text(Format.usd(day.costUSD)).monospacedDigit()
                }
                .font(.system(size: 12, weight: isToday ? .semibold : .regular))
            }
            Divider()
            GridRow {
                Text("합계")
                Text("")
                Text(Format.tokens(totals.map(\.tokens).reduce(0, +))).monospacedDigit()
                Text(Format.usd(totals.map(\.costUSD).reduce(0, +))).monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private func bar(fraction: Double, highlighted: Bool) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor.opacity(highlighted ? 0.9 : 0.5))
                .frame(width: max(geo.size.width * fraction, 2))
                .frame(maxHeight: .infinity)
        }
        .frame(width: 90, height: 6)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (E)"
        return f
    }()
}

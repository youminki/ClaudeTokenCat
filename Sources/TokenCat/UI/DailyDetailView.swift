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

            let totals = engine.snapshot?.dailyTotals ?? []
            if totals.isEmpty {
                Text("데이터 없음").foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("날짜").fontWeight(.semibold)
                        Text("토큰").fontWeight(.semibold).gridColumnAlignment(.trailing)
                        Text("비용(추정)").fontWeight(.semibold).gridColumnAlignment(.trailing)
                    }
                    .font(.system(size: 11))
                    Divider()
                    ForEach(totals, id: \.dayStart) { day in
                        GridRow {
                            Text(Self.dayFormatter.string(from: day.dayStart))
                            Text(day.tokens.formatted()).monospacedDigit()
                            Text(Format.usd(day.costUSD)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (E)"
        return f
    }()
}

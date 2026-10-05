import SwiftUI
import UsageCore

/// 러너 클릭 시 팝오버 (§F3 레이아웃).
/// 게이지 % = 공식 엔드포인트(보간 포함), 토큰량·속도·스파크라인 = 로컬 JSONL.
struct PopoverView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    var openSettings: () -> Void = {}
    var openDailyDetail: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            infoCard
            buttonColumn
        }
        .padding(14)
        .frame(width: 360)
    }

    // MARK: 좌측 정보 카드

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sessionSection
            Divider()
            weeklySection
            Divider()
            burnRateSection
            Divider()
            todaySection
            Divider()
            dataSourceFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 세션 (5시간)

    private var sessionSection: some View {
        let blockTokens = engine.snapshot?.currentBlock?.totalTokens ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            if let official = engine.official, let basePct = official.sessionPercent {
                let pct = GaugeMath.interpolated(base: basePct, windowTokens: blockTokens,
                                                 tokensSince: engine.tokensSinceOfficial)
                gaugeHeader(title: "🐱 세션 (5시간)", percent: pct, official: true)
                GaugeBar(fraction: pct / 100)
                captionRow(officialCaption(resetsAt: official.sessionResetsAt,
                                           fetchedAt: official.fetchedAt,
                                           interpolating: pct > basePct + 0.05))
                captionRow("Claude Code 소모: \(Format.tokens(blockTokens)) tokens (JSONL 집계)")
            } else {
                let limit = settings.estimatedSessionLimit
                let pct = Double(blockTokens) / Double(limit) * 100
                gaugeHeader(title: "🐱 세션 (5시간)", percent: pct, official: false)
                GaugeBar(fraction: pct / 100)
                captionRow("토큰: \(Format.tokens(blockTokens)) / 한도 \(Format.tokens(limit)) (추정)")
                if let block = engine.snapshot?.currentBlock {
                    captionRow(Format.resetCountdown(until: block.end))
                } else {
                    captionRow("활성 세션 없음 — 다음 활동 시 새 5시간 창 시작")
                }
            }
        }
    }

    // MARK: 주간

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let official = engine.official, let basePct = official.weeklyPercent {
                let pct = GaugeMath.interpolated(base: basePct,
                                                 windowTokens: engine.snapshot?.weeklyTokens ?? 0,
                                                 tokensSince: engine.tokensSinceOfficial)
                gaugeHeader(title: "📅 주간 사용량", percent: pct, official: true)
                GaugeBar(fraction: pct / 100)
                if let resetsAt = official.weeklyResetsAt {
                    captionRow("\(Format.weekdayTime(resetsAt)) 리셋 (공식)")
                }
            } else {
                let weeklyTokens = engine.snapshot?.weeklyTokens ?? 0
                let pct = Double(weeklyTokens) / Double(settings.estimatedWeeklyLimit) * 100
                gaugeHeader(title: "📅 주간 사용량", percent: pct, official: false)
                GaugeBar(fraction: pct / 100)
                let windowNote = settings.weeklyResetEnabled
                    ? "\(Format.weekdayName(settings.weeklyResetWeekday)) \(String(format: "%02d:00", settings.weeklyResetHour)) 리셋 (사용자 설정)"
                    : "롤링 7일 합계"
                captionRow("\(Format.tokens(weeklyTokens)) tokens · \(windowNote) (추정)")
            }
            if let shares = modelShares {
                captionRow("\(shares) (모델 비중, JSONL 기준)")
            }
        }
    }

    private var modelShares: String? {
        guard let modelTokens = engine.snapshot?.weeklyModelTokens, !modelTokens.isEmpty else { return nil }
        let total = modelTokens.values.reduce(0, +)
        guard total > 0 else { return nil }
        return modelTokens.sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\(Format.modelName($0.key)) \(Int((Double($0.value) / Double(total) * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    // MARK: 속도 / 오늘 / 푸터

    private var burnRateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🔥 현재 속도").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(engine.burnRate).formatted()) tok/min")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            Sparkline(values: engine.snapshot?.sparkline ?? [])
            captionRow("상태: \(engine.catState.label) \(engine.catState.emoji) · 최근 30분")
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("💰 오늘").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Format.tokens(engine.snapshot?.todayTokens ?? 0)) tokens · \(Format.usd(engine.snapshot?.todayCostUSD ?? 0)) (추정)")
                    .font(.system(size: 11)).monospacedDigit()
            }
            if let programmatic = engine.snapshot?.todayProgrammaticTokens, programmatic > 0 {
                captionRow("프로그래매틱(SDK) \(Format.tokens(programmatic)) tokens 포함 — 별도 크레딧 풀")
            }
        }
    }

    private var dataSourceFooter: some View {
        Button(action: openSettings) {
            HStack(spacing: 4) {
                Text("📦 데이터:")
                if engine.official != nil {
                    Text("공식 연동 ✓").foregroundStyle(.green)
                } else if settings.officialEnabled {
                    Text("추정 모드 (공식 조회 실패)").foregroundStyle(.orange)
                } else {
                    Text("추정 모드").foregroundStyle(.orange)
                }
                Text("· 플랜: \(settings.plan.displayName)")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 우측 버튼 열

    private var buttonColumn: some View {
        VStack(spacing: 8) {
            Button {
                settings.spriteTheme = settings.spriteTheme.next   // 🐾 색상 3종 순환
            } label: {
                Label("러너 색상: \(settings.spriteTheme.displayName)", systemImage: "pawprint")
            }
            Button(action: openDailyDetail) {
                Label("일별 상세", systemImage: "chart.bar")
            }
            Button { engine.refreshNow(forceOfficial: true) } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            Button(action: openSettings) {
                Label("설정", systemImage: "gearshape")
            }
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("종료", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
    }

    // MARK: 헬퍼

    private func gaugeHeader(title: String, percent: Double, official: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if official {
                Text("✓공식")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }
            Spacer()
            Text(String(format: "%.1f%%", percent))
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
        }
    }

    private func officialCaption(resetsAt: Date?, fetchedAt: Date, interpolating: Bool) -> String {
        var parts: [String] = []
        if let resetsAt { parts.append(Format.resetCountdown(until: resetsAt)) }
        let age = Int(Date().timeIntervalSince(fetchedAt) / 60)
        parts.append(age < 1 ? "공식 방금 전" : "공식 \(age)분 전")
        if interpolating { parts.append("보간 중") }
        return parts.joined(separator: " · ")
    }

    private func captionRow(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

enum Format {
    /// 1_240_000 → "1.24M", 532_100 → "532K"
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.2fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    static func resetCountdown(until end: Date, now: Date = Date()) -> String {
        let remaining = max(0, end.timeIntervalSince(now))
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return h > 0 ? "\(h)시간 \(m)분 후 리셋" : "\(m)분 후 리셋"
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["일", "월", "화", "수", "목", "금", "토"]
        return (1...7).contains(weekday) ? "\(names[weekday - 1])요일" : "?"
    }

    static func weekdayTime(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(weekdayName(weekday)) \(f.string(from: date))"
    }

    static func modelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("fable") { return "Fable" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }
}

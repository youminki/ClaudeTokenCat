import SwiftUI
import UsageCore

/// 러너 클릭 시 팝오버 (§F3 레이아웃).
/// 게이지 % = 공식 엔드포인트(보간 포함), 토큰량·속도·스파크라인 = 로컬 JSONL.
struct PopoverView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    var openSettings: () -> Void = {}
    var openDailyDetail: () -> Void = {}

    @StateObject private var sparklineHover = HoverIndex()

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
        let gauge = engine.sessionGauge
        let blockTokens = engine.snapshot?.currentBlock?.totalTokens ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            gaugeHeader(title: "🐱 세션 (5시간)", gauge: gauge)
            GaugeBar(percent: gauge.percent, basePercent: gauge.officialBase,
                     elapsed: elapsed(until: engine.sessionResetsAt, duration: BlockCalculator.blockDuration))
            if let official = engine.official, gauge.isOfficial {
                captionRow(officialCaption(resetsAt: official.sessionResetsAt, fetchedAt: official.fetchedAt,
                                           interpolating: gauge.isInterpolating))
                captionRow("Claude Code 소모: \(Format.tokens(blockTokens)) tokens (JSONL 집계)")
            } else {
                captionRow("토큰: \(Format.tokens(blockTokens)) / 한도 \(Format.tokens(settings.estimatedSessionLimit)) (추정)")
                if let block = engine.snapshot?.currentBlock {
                    captionRow(Format.resetCountdown(until: block.end))
                } else {
                    captionRow("활성 세션 없음, 다음 활동 때 새 5시간 창 시작")
                }
            }
            if gauge.percent < 100,
               let outlook = GaugeMath.limitOutlook(minutesLeft: engine.sessionMinutesLeft,
                                                    resetsAt: engine.sessionResetsAt, now: Date()) {
                switch outlook {
                case .reachesLimit(let minutes):
                    captionRow("⏱ 지금 속도면 약 \(Format.minutes(minutes)) 뒤 한도 (리셋 전)",
                               emphasized: gauge.percent >= 80)
                case .clearUntilReset:
                    captionRow("⏱ 지금 속도로는 리셋까지 한도 여유")
                }
            }
        }
    }

    // MARK: 주간

    private var weeklySection: some View {
        let gauge = engine.weeklyGauge
        let weeklyTokens = engine.snapshot?.weeklyTokens ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            gaugeHeader(title: "📅 주간 사용량", gauge: gauge)
            GaugeBar(percent: gauge.percent, basePercent: gauge.officialBase,
                     elapsed: elapsed(until: weeklyResetsAt, duration: WeeklyWindow.duration))
            if gauge.isOfficial {
                if let reset = engine.nextWeeklyReset {
                    captionRow("\(Format.weekdayTime(reset)) 리셋 · \(Format.duration(reset.timeIntervalSinceNow)) 남음")
                }
            } else {
                captionRow("\(Format.tokens(weeklyTokens)) tokens · \(weeklyWindowNote) (추정)")
            }
            if let shares = modelShares {
                captionRow("\(shares) (모델 비중, JSONL 기준)")
            }
        }
    }

    /// 주간 창의 다음 리셋. 공식 값을 모르고 롤링 7일이면 창 경계가 없어 nil.
    private var weeklyResetsAt: Date? {
        if let reset = engine.nextWeeklyReset { return reset }
        guard settings.weeklyResetEnabled else { return nil }
        return WeeklyWindow.lastReset(weekday: settings.weeklyResetWeekday, hour: settings.weeklyResetHour)
            .addingTimeInterval(WeeklyWindow.duration)
    }

    private var weeklyWindowNote: String {
        if let reset = engine.nextWeeklyReset {
            return "\(Format.weekdayTime(reset)) 리셋 (마지막 공식 기준)"
        }
        if settings.weeklyResetEnabled {
            return "\(Format.weekdayName(settings.weeklyResetWeekday)) \(Format.hour(settings.weeklyResetHour)) 리셋 (사용자 설정)"
        }
        return "롤링 7일 합계"
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
        let sparkline = engine.snapshot?.sparkline ?? []
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🔥 현재 속도").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(engine.burnRate).formatted()) tok/min")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            Sparkline(values: sparkline, hoverIndex: $sparklineHover.index)
            HStack {
                if let i = sparklineHover.index, sparkline.indices.contains(i) {
                    let minutesAgo = sparkline.count - 1 - i
                    captionRow("\(minutesAgo == 0 ? "지금" : "\(minutesAgo)분 전") · \(Format.tokens(sparkline[i]))/분")
                } else {
                    captionRow("상태: \(engine.catState.label) \(engine.catState.emoji) · 최근 30분")
                }
                Spacer()
                if let peak = sparkline.max(), peak > 0 {
                    captionRow("최고 \(Format.tokens(peak))/분")
                }
            }
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
                captionRow("프로그래매틱(SDK) \(Format.tokens(programmatic)) tokens 포함, 별도 크레딧 풀")
            }
        }
    }

    private var dataSourceFooter: some View {
        Button(action: openSettings) {
            HStack(spacing: 4) {
                Text("📦 데이터:")
                Text(statusText).foregroundStyle(statusColor).lineLimit(1)
                Text("· 플랜: \(settings.plan.displayName)").lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("설정 열기")
    }

    private var statusText: String {
        switch engine.officialStatus {
        case .live: return "공식 연동 ✓"
        case .waiting: return "공식 조회 중…"
        case .stale(let reason): return "공식 (최근 조회 실패: \(reason))"
        case .failed(let reason): return "추정 모드 (\(reason))"
        case .disabled: return "추정 모드"
        }
    }

    private var statusColor: Color {
        switch engine.officialStatus {
        case .live: return .green
        case .waiting: return .secondary
        case .stale, .failed, .disabled: return .orange
        }
    }

    // MARK: 우측 버튼 열

    private var buttonColumn: some View {
        VStack(spacing: 8) {
            Menu {
                Picker("러너", selection: $settings.runner) {
                    ForEach(Runner.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("색상", selection: $settings.spriteTheme) {
                    ForEach(SpriteTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("러너", systemImage: "pawprint")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("러너·색상 바꾸기 (지금: \(settings.runner.displayName), \(settings.spriteTheme.displayName))")
            Button(action: openDailyDetail) {
                Label("일별 상세", systemImage: "chart.bar")
            }
            .help("일별 사용 내역")
            Button { engine.refreshNow(forceOfficial: true) } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("새로고침 (⌘R)")
            Button(action: openSettings) {
                Label("설정", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .help("설정 (⌘,)")
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("종료", systemImage: "power")
            }
            .keyboardShortcut("q")
            .help("TokenCat 종료 (⌘Q)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
    }

    // MARK: 헬퍼

    private func gaugeHeader(title: String, gauge: GaugeReading) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if gauge.isOfficial {
                Text("✓공식")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            } else {
                Text("추정")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(gauge.percent > 999 ? ">999%" : Format.percent(gauge.percent))
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(gauge.percent >= 80 ? GaugeBar.color(for: gauge.percent) : .primary)
        }
    }

    private func elapsed(until resetsAt: Date?, duration: TimeInterval) -> Double? {
        resetsAt.map { GaugeMath.elapsedFraction(resetsAt: $0, duration: duration, now: Date()) }
    }

    private func officialCaption(resetsAt: Date?, fetchedAt: Date, interpolating: Bool) -> String {
        var parts: [String] = []
        if let resetsAt { parts.append(Format.resetCountdown(until: resetsAt)) }
        let age = Int(Date().timeIntervalSince(fetchedAt) / 60)
        parts.append(age < 1 ? "공식 방금 전" : "공식 \(age)분 전")
        if interpolating { parts.append("이후 사용분 반영") }
        return parts.joined(separator: " · ")
    }

    private func captionRow(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(emphasized ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
    }
}

/// 스파크라인에서 마우스가 가리키는 분. `@State`를 못 쓰는 이유는 CalibrationForm 참고.
final class HoverIndex: ObservableObject {
    @Published var index: Int?
}

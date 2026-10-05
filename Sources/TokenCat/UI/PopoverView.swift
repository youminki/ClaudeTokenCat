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
        VStack(alignment: .leading, spacing: 12) {
            sessionSection
            Divider()
            weeklySection
            Divider()
            speedSection
            Divider()
            todaySection
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 세션 (5시간)

    private var sessionSection: some View {
        let gauge = engine.sessionGauge
        let blockTokens = engine.snapshot?.currentBlock?.totalTokens ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            header("세션", detail: "5시간", gauge: gauge)
                .help("이번 세션에 Claude Code가 쓴 토큰: \(Format.tokens(blockTokens))")
            GaugeBar(percent: gauge.percent, basePercent: gauge.officialBase,
                     elapsed: elapsed(until: engine.sessionResetsAt, duration: BlockCalculator.blockDuration))
            HStack {
                if let reset = engine.sessionResetsAt {
                    caption(Format.resetCountdown(until: reset))
                } else {
                    caption("사용 기록이 생기면 5시간 세션 시작")
                }
                Spacer()
                if let official = engine.official, gauge.isOfficial {
                    caption(updatedText(official.fetchedAt))
                } else {
                    caption("\(Format.tokens(blockTokens)) / \(Format.tokens(settings.estimatedSessionLimit)) 토큰")
                }
            }
            if gauge.percent < 100,
               let outlook = GaugeMath.limitOutlook(minutesLeft: engine.sessionMinutesLeft,
                                                    resetsAt: engine.sessionResetsAt, now: Date()) {
                switch outlook {
                case .reachesLimit(let minutes):
                    caption("현재 속도로 약 \(Format.minutes(minutes)) 뒤 한도 도달", emphasized: gauge.percent >= 80)
                case .clearUntilReset:
                    caption("현재 속도로는 초기화 전까지 여유")
                }
            }
        }
    }

    // MARK: 주간

    private var weeklySection: some View {
        let gauge = engine.weeklyGauge
        let weeklyTokens = engine.snapshot?.weeklyTokens ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            header("주간", detail: nil, gauge: gauge)
            GaugeBar(percent: gauge.percent, basePercent: gauge.officialBase,
                     elapsed: elapsed(until: weeklyResetsAt, duration: WeeklyWindow.duration))
            if gauge.isOfficial, let reset = engine.nextWeeklyReset {
                caption("\(Format.weekdayTime(reset)) 초기화 · \(Format.duration(reset.timeIntervalSinceNow)) 남음")
            } else if !gauge.isOfficial {
                caption("\(Format.tokens(weeklyTokens)) 토큰 · \(weeklyWindowNote)")
            }
            if let shares = modelShares {
                caption(shares)
                    .help("이번 주 Claude Code 사용 토큰의 모델 비중")
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
            return "\(Format.weekdayTime(reset)) 초기화"
        }
        if settings.weeklyResetEnabled {
            return "\(Format.weekdayName(settings.weeklyResetWeekday)) \(Format.hour(settings.weeklyResetHour)) 초기화"
        }
        return "최근 7일"
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

    private var speedSection: some View {
        let sparkline = engine.snapshot?.sparkline ?? []
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("속도").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(engine.burnRate).formatted()) 토큰/분")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Sparkline(values: sparkline, hoverIndex: $sparklineHover.index)
            HStack {
                if let i = sparklineHover.index, sparkline.indices.contains(i) {
                    let minutesAgo = sparkline.count - 1 - i
                    caption("\(minutesAgo == 0 ? "지금" : "\(minutesAgo)분 전") · \(Format.tokens(sparkline[i])) 토큰/분")
                } else {
                    caption("\(engine.catState.label) · 최근 30분")
                }
                Spacer()
                if let peak = sparkline.max(), peak > 0 {
                    caption("최고 \(Format.tokens(peak))/분")
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Format.tokens(engine.snapshot?.todayTokens ?? 0)) 토큰 · 약 \(Format.usd(engine.snapshot?.todayCostUSD ?? 0))")
                    .font(.system(size: 12)).monospacedDigit()
                    .help("API 단가로 환산한 추정 비용")
            }
            if let programmatic = engine.snapshot?.todayProgrammaticTokens, programmatic > 0 {
                caption("SDK 사용 \(Format.tokens(programmatic)) 토큰 포함 (별도 한도)")
            }
        }
    }

    private var footer: some View {
        Button(action: openSettings) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("설정 열기")
    }

    private var statusText: String {
        switch engine.officialStatus {
        case .live: return "공식 사용량 연동 중"
        case .waiting: return "공식 사용량 조회 중"
        case .stale(let reason): return "직전 공식 값 사용 중 · \(reason)"
        case .failed(let reason): return "추정 모드 · \(reason)"
        case .disabled: return "추정 모드 · \(settings.plan.displayName) 플랜 기준"
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
                Label("일별 사용량", systemImage: "chart.bar.xaxis")
            }
            .help("일별 사용량")
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

    private func header(_ title: String, detail: String?, gauge: GaugeReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !gauge.isOfficial {
                Text("추정")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .help("공식 사용량을 받지 못해 로컬 기록과 추정 한도로 계산한 값")
            }
            Spacer()
            Text(gauge.percent > 999 ? ">999%" : Format.percent(gauge.percent))
                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(gauge.percent >= 80 ? GaugeBar.color(for: gauge.percent) : .primary)
        }
    }

    private func elapsed(until resetsAt: Date?, duration: TimeInterval) -> Double? {
        resetsAt.map { GaugeMath.elapsedFraction(resetsAt: $0, duration: duration, now: Date()) }
    }

    private func updatedText(_ fetchedAt: Date) -> String {
        let age = Int(Date().timeIntervalSince(fetchedAt) / 60)
        return age < 1 ? "방금 갱신" : "\(age)분 전 갱신"
    }

    private func caption(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(emphasized ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            .lineLimit(1)
    }
}

/// 스파크라인에서 마우스가 가리키는 분. `@State`를 못 쓰는 이유는 CalibrationForm 참고.
final class HoverIndex: ObservableObject {
    @Published var index: Int?
}

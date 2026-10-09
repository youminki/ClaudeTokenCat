import SwiftUI
import UsageCore

/// 러너 클릭 시 팝오버 (§F3). 맨 위는 러너가 달리는 무대, 아래는 세션·주간·속도·오늘.
/// 게이지 % = 공식 엔드포인트, 토큰량·속도·스파크라인 = 로컬 JSONL.
struct PopoverView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    var openSettings: () -> Void = {}
    var openDailyDetail: () -> Void = {}
    var openLeaderboard: () -> Void = {}
    /// 무대에서 러너를 누르거나 메뉴에서 동작을 고르면 메뉴바 러너도 같은 동작을 한다.
    var performTrick: (Trick) -> Void = { _ in }

    @StateObject private var sparklineHover = HoverIndex()
    @ObservedObject private var customRunners = CustomRunnerStore.shared
    @ObservedObject private var petdex = PetdexStore.shared

    /// 메뉴의 기본 러너 선택. 내 러너를 쓰는 중이면 아무 것도 체크하지 않는다.
    private var builtInSelection: Binding<Runner?> {
        Binding(get: { settings.customRunnerID == nil ? settings.runner : nil },
                set: { if let runner = $0 { settings.select(runner) } })
    }

    private var customSelection: Binding<String?> {
        Binding(get: { settings.customRunnerID },
                set: { id in
                    if let pack = LocalPack.runner(storageID: id) {
                        settings.select(pack)
                    } else if petdex.pet(storageID: id) != nil {
                        settings.customRunnerID = id
                    } else if let custom = customRunners.runner(id: id) {
                        settings.select(custom)
                    }
                })
    }

    /// 기본 러너, 개인 팩, Petdex 펫, 내 러너를 통틀어 지금과 다른 러너 하나.
    private func pickRandomRunner() {
        let builtIns = Runner.allCases.filter { settings.customRunnerID != nil || $0 != settings.runner }
        let others = (LocalPack.runners.map(LocalPack.storageID) + petdex.pets.map { PetdexStore.storageID($0.slug) }
            + customRunners.runners.map(\.id)).filter { $0 != settings.customRunnerID }
        let index = Int.random(in: 0..<(builtIns.count + others.count))
        if index < builtIns.count {
            settings.select(builtIns[index])
        } else {
            customSelection.wrappedValue = others[index - builtIns.count]
        }
    }

    private var display: SpriteDisplay {
        SpriteDisplay(state: engine.catState, level: engine.alertLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunnerStage(display: display, character: settings.character, theme: settings.spriteTheme,
                        onPet: performTrick, openLeaderboard: openLeaderboard)
            stageCaption.padding(.top, 9)
            Hairline().padding(.vertical, 14)
            HStack(alignment: .top, spacing: 20) {
                sessionColumn
                weeklyColumn
            }
            Hairline().padding(.vertical, 14)
            speedSection
            Hairline().padding(.vertical, 14)
            todayRow
            Hairline().padding(.top, 14)
            footer.padding(.top, 8)
        }
        .padding(16)
        .frame(width: 376)
    }

    // MARK: 무대 아래 한 줄

    private var stageCaption: some View {
        HStack(spacing: 0) {
            runnerMenu
            Spacer(minLength: 8)
            Text(engine.burnRate >= 1 ? "\(Int(engine.burnRate).formatted()) 토큰/분" : "멈춤")
                .font(Theme.caption.monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
    }

    private var stateLabel: String {
        switch display {
        case .normal(let state): return state.label
        case .tired: return "지침"
        case .alert: return "한도 임박"
        }
    }

    /// 러너 이름이 곧 메뉴 버튼: 러너·색상 바꾸기, 동작 해보기.
    private var runnerMenu: some View {
        Menu {
            ForEach(Runner.Group.allCases, id: \.self) { group in
                Picker(group.rawValue, selection: builtInSelection) {
                    ForEach(Runner.runners(in: group), id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
            }
            if !LocalPack.runners.isEmpty {
                // 개인 팩과 Petdex는 수십~백 명이라 펼쳐 두면 메뉴가 화면을 넘는다
                Picker("개인 팩", selection: customSelection) {
                    ForEach(LocalPack.runners, id: \.id) { Text($0.name).tag(Optional(LocalPack.storageID($0))) }
                }
                .pickerStyle(.menu)
            }
            if !petdex.pets.isEmpty {
                Picker("Petdex", selection: customSelection) {
                    ForEach(petdex.pets) { Text($0.name).tag(Optional(PetdexStore.storageID($0.slug))) }
                }
                .pickerStyle(.menu)
            }
            if !customRunners.runners.isEmpty {
                Picker("내 러너", selection: customSelection) {
                    ForEach(customRunners.runners) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
            }
            Button("아무거나", action: pickRandomRunner)
            Divider()
            Picker("색상", selection: $settings.spriteTheme) {
                ForEach(SpriteTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Menu("동작 해보기") {
                ForEach(Trick.allCases.filter { Trick.awake.contains($0) }, id: \.self) { trick in
                    Button(trick.label) { performTrick(trick) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(settings.character.name).foregroundStyle(Theme.primary)
                Text("·").foregroundStyle(Theme.tertiary)
                Text(stateLabel).foregroundStyle(display == .alert ? Theme.critical : Theme.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .font(Theme.label)
        }
        // 기본 메뉴 스타일은 레이블을 제 모양으로 바꾼다. 버튼 스타일로 두면 레이블을 그대로 그린다.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("러너·색상 바꾸기, 동작 해보기")
    }

    // MARK: 세션 · 주간

    private var sessionColumn: some View {
        let gauge = engine.sessionGauge
        return VStack(alignment: .leading, spacing: 0) {
            columnTitle("세션", detail: "5시간")
            figure(gauge).padding(.top, 2)
            GaugeBar(percent: gauge?.percent,
                     elapsed: elapsed(until: engine.sessionResetsAt, duration: BlockCalculator.blockDuration))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                if gauge == nil {
                    caption(unavailableNote)
                } else if gauge?.source == .rolledOver {
                    caption("초기화됨 · 새 값 확인 중")
                } else if let reset = engine.sessionResetsAt {
                    caption(Format.resetCountdown(until: reset))
                } else {
                    caption("사용하면 5시간 창 시작")
                }
                sessionOutlook
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("이번 세션에 이 기기의 Claude Code가 쓴 토큰: \(Format.tokens(engine.snapshot?.currentBlock?.totalTokens ?? 0))")
    }

    @ViewBuilder
    private var sessionOutlook: some View {
        if let gauge = engine.sessionGauge, gauge.percent < 100,
           let outlook = GaugeMath.limitOutlook(minutesLeft: engine.sessionMinutesLeft,
                                                resetsAt: engine.sessionResetsAt, now: Date()) {
            switch outlook {
            case .reachesLimit(let minutes):
                caption("약 \(Format.minutes(minutes)) 뒤 한도", color: gauge.percent >= 80 ? Theme.warning : Theme.tertiary)
            case .clearUntilReset:
                caption("초기화 전까지 여유", color: Theme.tertiary)
            }
        }
    }

    private var weeklyColumn: some View {
        let gauge = engine.weeklyGauge
        return VStack(alignment: .leading, spacing: 0) {
            columnTitle("주간", detail: nil)
            figure(gauge).padding(.top, 2)
            GaugeBar(percent: gauge?.percent,
                     elapsed: gauge == nil ? nil : elapsed(until: engine.nextWeeklyReset, duration: WeeklyWindow.duration))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                if gauge == nil {
                    caption(unavailableNote)
                } else if let reset = engine.nextWeeklyReset {
                    caption("\(Format.weekdayTime(reset)) 초기화")
                } else {
                    caption("사용하면 7일 창 시작")
                }
                if let shares = weeklyShares {
                    caption(shares, color: Theme.tertiary)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnTitle(_ title: String, detail: String?) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(Theme.secondary)
            if let detail { Text(detail).foregroundStyle(Theme.tertiary) }
        }
        .font(Theme.label)
    }

    /// 공식 값이 없으면 "--". 로컬 기록으로 추정하면 `/usage`와 어긋나서 숫자를 지어내지 않는다.
    private func figure(_ gauge: GaugeReading?) -> some View {
        let percent = gauge?.percent ?? 0
        return Figure(value: gauge.map { "\($0.displayPercent)" } ?? "--", unit: "%",
                      color: gauge == nil ? Theme.tertiary : percent >= 80 ? Theme.level(percent) : Theme.primary)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: gauge?.displayPercent)
    }

    /// 게이지를 비운 이유. 자세한 사유는 아래 상태 줄에 있다.
    private var unavailableNote: String {
        switch engine.officialStatus {
        case .waiting: return "공식 값 조회 중"
        case .disabled: return "공식 연동 꺼짐"
        case .failed: return "조회 실패"
        case .live, .stale: return "공식 값 없음"   // 응답에 이 창이 빠졌을 때
        }
    }

    /// 사용처가 둘 이상이면 공식 비중(Claude Code·채팅…), 아니면 이 기기의 모델 비중.
    private var weeklyShares: String? {
        let used = engine.weeklyBreakdown.filter { $0.percent >= 1 }.sorted { $0.percent > $1.percent }
        if used.count > 1 {
            return used.prefix(2).map { "\($0.name) \(Int($0.percent))%" }.joined(separator: " · ")
        }
        guard let modelTokens = engine.snapshot?.weeklyModelTokens, !modelTokens.isEmpty else { return nil }
        let total = modelTokens.values.reduce(0, +)
        guard total > 0 else { return nil }
        return modelTokens.sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\(Format.modelName($0.key)) \(Int((Double($0.value) / Double(total) * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    // MARK: 속도 · 오늘

    private var speedSection: some View {
        let sparkline = engine.snapshot?.sparkline ?? []
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("최근 30분").font(Theme.label).foregroundStyle(Theme.secondary)
                Spacer()
                if let i = sparklineHover.index, sparkline.indices.contains(i) {
                    let minutesAgo = sparkline.count - 1 - i
                    caption("\(minutesAgo == 0 ? "지금" : "\(minutesAgo)분 전") \(Format.tokens(sparkline[i]))/분",
                            color: Theme.primary)
                } else if let peak = sparkline.max(), peak > 0 {
                    caption("최고 \(Format.tokens(peak))/분", color: Theme.tertiary)
                }
            }
            Sparkline(values: sparkline, hoverIndex: $sparklineHover.index)
        }
    }

    private var todayRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘").font(Theme.label).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(Format.tokens(engine.snapshot?.todayTokens ?? 0)) 토큰")
                    .font(Theme.value)
                    .foregroundStyle(Theme.primary)
                Text("약 \(Format.usd(engine.snapshot?.todayCostUSD ?? 0))")
                    .font(Theme.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .help("API 단가로 환산한 추정 비용")
            }
            if let programmatic = engine.snapshot?.todayProgrammaticTokens, programmatic > 0 {
                caption("SDK 사용 \(Format.tokens(programmatic)) 토큰 포함 (별도 한도)", color: Theme.tertiary)
            }
        }
    }

    // MARK: 상태 · 도구

    private var footer: some View {
        HStack(spacing: 2) {
            Button(action: openSettings) {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(statusText).lineLimit(1)
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("설정 열기")
            Spacer(minLength: 8)
            Button(action: openDailyDetail) { Image(systemName: "chart.bar") }
                .help("일별 사용량")
            Button { engine.refreshNow(forceOfficial: true) } label: { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r")
                .help("새로고침 (⌘R)")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .keyboardShortcut(",")
                .help("설정 (⌘,)")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(ToolbarButtonStyle(tint: Theme.critical))
                .keyboardShortcut("q")
                .help("RunTime 종료 (⌘Q)")
        }
        .buttonStyle(ToolbarButtonStyle())
    }

    private var statusText: String {
        switch engine.officialStatus {
        case .live:
            guard let official = engine.official else { return "공식 사용량" }
            let age = Int(Date().timeIntervalSince(official.fetchedAt) / 60)
            return age < 1 ? "공식 사용량 · 방금 갱신" : "공식 사용량 · \(age)분 전 갱신"
        case .waiting: return "공식 사용량 조회 중"
        case .stale(let reason): return "직전 공식 값 · \(reason)"
        case .failed(let reason): return "조회 실패 · \(reason)"
        case .disabled: return "공식 연동 꺼짐"
        }
    }

    private var statusColor: Color {
        switch engine.officialStatus {
        case .live: return Theme.positive
        case .waiting, .disabled: return Theme.tertiary
        case .stale, .failed: return Theme.warning
        }
    }

    // MARK: 헬퍼

    private func elapsed(until resetsAt: Date?, duration: TimeInterval) -> Double? {
        resetsAt.map { GaugeMath.elapsedFraction(resetsAt: $0, duration: duration, now: Date()) }
    }

    private func caption(_ text: String, color: Color = Theme.secondary) -> some View {
        Text(text)
            .font(Theme.caption.monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// 스파크라인에서 마우스가 가리키는 분. `@State`를 못 쓰는 이유는 HoverFlag 참고.
final class HoverIndex: ObservableObject {
    @Published var index: Int?
}

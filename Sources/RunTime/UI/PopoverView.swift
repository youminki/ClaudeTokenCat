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
            stageCaption.padding(.top, 10).padding(.horizontal, 2)
            // 세션과 주간을 나란히 두어 두 값을 한눈에 견준다
            Card(padding: 0) {
                HStack(alignment: .top, spacing: 0) {
                    sessionRow
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    weeklyRow
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    activitySection.padding(12)
                    Hairline()
                    statColumns
                }
            }
            .padding(.top, 8)
            footer.padding(.top, 10)
        }
        .padding(14)
        .frame(width: 376)
    }

    // MARK: 무대 아래 한 줄

    private var stageCaption: some View {
        HStack(spacing: 0) {
            runnerMenu
            Spacer(minLength: 8)
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

    private var sessionRow: some View {
        let gauge = engine.sessionGauge
        let elapsed = gauge == nil ? nil : elapsed(until: engine.sessionResetsAt, duration: BlockCalculator.blockDuration)
        let detail: String
        if gauge == nil {
            detail = unavailableNote
        } else if gauge?.source == .rolledOver {
            detail = "초기화됨 · 새 값 확인 중"
        } else if let reset = engine.sessionResetsAt {
            detail = Format.resetCountdown(until: reset)
        } else {
            detail = "사용하면 5시간 창 시작"
        }
        return limitRow(title: "세션", window: "5시간", gauge: gauge, elapsed: elapsed, detail: detail,
                        reachesLimit: sessionReachesLimit) { sessionOutlook }
            .help("이번 세션에 이 Mac의 Claude Code가 쓴 토큰: \(Format.tokens(engine.snapshot?.currentBlock?.totalTokens ?? 0))"
                  + elapsedNote(elapsed))
    }

    private var weeklyRow: some View {
        let gauge = engine.weeklyGauge
        let elapsed = gauge == nil ? nil : elapsed(until: engine.nextWeeklyReset, duration: WeeklyWindow.duration)
        let detail: String
        if gauge == nil {
            detail = unavailableNote
        } else if let reset = engine.nextWeeklyReset {
            detail = "\(Format.weekdayTime(reset)) 초기화"
        } else {
            detail = "사용하면 7일 창 시작"
        }
        return limitRow(title: "주간", window: "7일", gauge: gauge, elapsed: elapsed, detail: detail, reachesLimit: false) {
            if let shares = weeklyShares { caption(shares, color: Theme.tertiary) }
        }
        .help(elapsedNote(elapsed).trimmingCharacters(in: .newlines))
    }

    /// 한도 한 칸: 이름과 속도 배지, 큰 %, 시간 눈금이 있는 막대, 초기화 시각.
    private func limitRow<Extra: View>(title: String, window: String, gauge: GaugeReading?, elapsed: Double?,
                                       detail: String, reachesLimit: Bool,
                                       @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                Text(window).font(Theme.caption).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 2)
                paceBadge(gauge: gauge, elapsed: elapsed, reachesLimit: reachesLimit)
            }
            .frame(height: 18)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(gauge.map { "\($0.displayPercent)" } ?? "--")
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(gauge == nil ? Theme.tertiary : gauge!.percent >= 80 ? Theme.ring(gauge!.percent) : Theme.primary)
            .animation(.easeOut(duration: 0.25), value: gauge?.displayPercent)
            .padding(.top, 4)
            GaugeBar(percent: gauge?.percent, elapsed: elapsed)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                caption(detail)
                extra()
            }
            .padding(.top, 7)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 최근 속도로는 초기화 전에 한도에 닿는지. 평균 페이스가 여유여도 배지를 빠름으로 올려 아래 문구와 맞춘다.
    private var sessionReachesLimit: Bool {
        guard case .reachesLimit = GaugeMath.limitOutlook(minutesLeft: engine.sessionMinutesLeft,
                                                         resetsAt: engine.sessionResetsAt, now: Date()) else { return false }
        return true
    }

    private func elapsedNote(_ elapsed: Double?) -> String {
        elapsed.map { "\n막대 위 눈금: 이번 창 시간의 \(Int(($0 * 100).rounded()))% 지남" } ?? ""
    }

    /// 시간 대비 속도 배지. 눈금을 읽지 않아도 지금 페이스가 보이게 한다.
    @ViewBuilder
    private func paceBadge(gauge: GaugeReading?, elapsed: Double?, reachesLimit: Bool) -> some View {
        if let gauge, gauge.source != .rolledOver, let elapsed {
            let pace = GaugeMath.pace(percent: gauge.percent, elapsed: elapsed)
            PaceBadge(pace: reachesLimit && (pace == .relaxed || pace == .steady) ? .fast : pace)
                .help("사용 \(gauge.displayPercent)% · 시간 \(Int((elapsed * 100).rounded()))% 지남"
                      + (reachesLimit ? "\n최근 속도로는 초기화 전에 한도에 닿습니다" : ""))
        }
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
        // 반올림해 0%가 되는 모델은 뺀다 ("Sonnet 0%"는 정보가 없다)
        return modelTokens.map { (Format.modelName($0.key), Int((Double($0.value) / Double(total) * 100).rounded())) }
            .filter { $0.1 >= 1 }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map { "\($0.0) \($0.1)%" }
            .joined(separator: " · ")
    }

    // MARK: 속도 · 오늘

    private var activitySection: some View {
        let values = engine.snapshot?.sparkline ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("최근 30분").font(Theme.label).foregroundStyle(Theme.secondary)
                Spacer()
                if let i = sparklineHover.index, values.indices.contains(i) {
                    let minutesAgo = values.count - 1 - i
                    caption("\(minutesAgo == 0 ? "지금" : "\(minutesAgo)분 전") \(Format.tokens(values[i]))/분",
                            color: Theme.primary)
                } else if let peak = values.max(), peak > 0 {
                    caption("최고 \(Format.tokens(peak))/분", color: Theme.tertiary)
                } else {
                    caption("쓴 기록 없음", color: Theme.tertiary)
                }
            }
            Sparkline(values: values, hoverIndex: $sparklineHover.index)
            HStack {
                Text("30분 전")
                Spacer()
                Text("지금")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.tertiary)
        }
    }

    /// 오늘 쓴 양, 예상 비용, 지금 속도. 모두 이 Mac의 Claude Code 기록 기준.
    private var statColumns: some View {
        let today = engine.snapshot?.todayTokens ?? 0
        let programmatic = engine.snapshot?.todayProgrammaticTokens ?? 0
        return HStack(spacing: 0) {
            StatColumn(label: programmatic > 0 ? "오늘 (SDK 포함)" : "오늘", value: Format.tokens(today), unit: "토큰")
                .help(programmatic > 0 ? "SDK 사용 \(Format.tokens(programmatic)) 토큰 포함 (별도 한도)" : "이 Mac의 Claude Code 기록 기준")
            Rectangle().fill(Theme.hairline).frame(width: 1)
            StatColumn(label: "추정 비용", value: Format.usd(engine.snapshot?.todayCostUSD ?? 0))
                .help("오늘 쓴 토큰을 API 단가로 환산한 참고값")
            Rectangle().fill(Theme.hairline).frame(width: 1)
            StatColumn(label: "지금 속도", value: engine.burnRate >= 1 ? Format.tokens(Int(engine.burnRate)) : "0", unit: "/분")
                .help("최근 1분 동안 쓴 토큰")
        }
        .fixedSize(horizontal: false, vertical: true)
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

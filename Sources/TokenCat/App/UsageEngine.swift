import Foundation
import Combine
import os.log
import UsageCore

/// 공식 usage 연동 상태 (팝오버 푸터·설정 화면 표시용).
enum OfficialStatus: Equatable {
    case disabled
    case waiting                  // 첫 조회 전
    case live
    case stale(reason: String)    // 조회 실패, 직전 공식 값 유지 중
    case failed(reason: String)   // 조회 실패, 추정 모드
}

/// JSONL 감시 → 집계 → burn rate → 고양이 상태 + 공식 % 폴링 + 한도 알림을 묶는 엔진.
/// 역할 분담(§2 하이브리드): 게이지 % = 공식 엔드포인트, 속도·토큰량·스파크라인 = 로컬 JSONL.
final class UsageEngine: ObservableObject {

    @Published var snapshot: UsageStore.Snapshot?
    @Published var burnRate: Double = 0
    @Published var catState: CatState = .sleeping
    /// 한도 임박 오버라이드 (§F2: 80% 🥵, 95% ⚠️). 세션/주간 중 높은 쪽 기준.
    @Published var alertLevel: UsageAlertLevel = .normal

    /// 마지막 공식 usage 성공 응답. nil = 미조회/실패/연동 off → 추정 모드 폴백.
    @Published var official: OfficialUsage?
    @Published var officialStatus: OfficialStatus = .waiting
    @Published var sessionGauge = GaugeReading(percent: 0, officialBase: nil)
    @Published var weeklyGauge = GaugeReading(percent: 0, officialBase: nil)
    /// 현재 속도로 세션 한도에 닿기까지 남은 분. 속도가 없으면 nil.
    @Published var sessionMinutesLeft: Int?
    /// 공식 응답에서 알아낸 다음 주간 리셋. 조회가 끊겨도 7일 단위로 굴려 유지한다.
    @Published var nextWeeklyReset: Date?

    let settings: AppSettings

    /// 공식 폴링 간격 180초 고정 (429 방지 안전 간격).
    static let officialPollInterval: TimeInterval = 180
    /// 팝오버 열 때 재조회 생략 기준: 직전 조회 30초 이내.
    static let officialRefreshThrottle: TimeInterval = 30
    /// 조회가 실패해도 이 시간 안의 공식 값은 계속 쓴다. 일시적 실패로 게이지가 추정값으로 튀지 않게.
    static let officialGrace: TimeInterval = 15 * 60
    /// 429를 받으면 이만큼 조회를 쉰다.
    static let rateLimitBackoff: TimeInterval = 10 * 60

    private let watcher = JSONLWatcher()
    private let store = UsageStore()
    private let meter = BurnRateMeter()
    private let provider = OAuthUsageProvider()
    private let workQueue = DispatchQueue(label: "tokencat.engine", qos: .utility)
    private var jsonlTimer: DispatchSourceTimer?
    private var officialTimer: DispatchSourceTimer?
    private var activityToken: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    // 이하 상태는 workQueue 전용
    private var pollInterval: TimeInterval = 3
    private var clientVersion: String?
    private var alertTracker = LimitAlertTracker()
    private var lastBlockStart: Date?
    private var lastTickAt: Date?
    private var lastOfficialAttempt: Date?
    private var officialInFlight = false
    private var officialBackoffUntil: Date?
    private var lastOfficialFailure = ""
    private var knownWeeklyReset: Date?
    private var lastAutoCalibratedFetch: Date?

    /// 진단용: `log stream --predicate 'subsystem == "dev.tokencat.TokenCat"' --info`
    private let log = Logger(subsystem: "dev.tokencat.TokenCat", category: "engine")

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func start() {
        let interval = settings.pollInterval
        log.info("엔진 시작: 폴링 \(interval)s, 공식 폴링 \(Self.officialPollInterval)s")
        // App Nap 방지: 메뉴바 전용 앱은 냅 대상이 되어 백그라운드 타이머가
        // 지연·정지될 수 있다(고양이 애니메이션은 돌지만 데이터만 멈춘 것처럼 보임).
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "토큰 사용량 폴링")

        let jsonlTimer = DispatchSource.makeTimerSource(queue: workQueue)
        jsonlTimer.setEventHandler { [weak self] in self?.tick() }
        self.jsonlTimer = jsonlTimer
        workQueue.async { self.applyPollInterval(interval) }
        jsonlTimer.resume()

        let officialTimer = DispatchSource.makeTimerSource(queue: workQueue)
        officialTimer.schedule(deadline: .now() + 1, repeating: Self.officialPollInterval)
        officialTimer.setEventHandler { [weak self] in self?.fetchOfficial(minInterval: 0) }
        officialTimer.resume()
        self.officialTimer = officialTimer

        settings.$pollInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.workQueue.async { self?.applyPollInterval(interval) }
            }
            .store(in: &cancellables)
    }

    /// JSONL 즉시 재스캔 + 공식 재조회.
    /// 팝오버 열림: 30초 스로틀(§F3). 새로고침 버튼: forceOfficial=true로 우회
    /// (연타 방지 5초만 유지) — 버튼이 팝오버 열림 직후 스로틀에 걸려 아무것도
    /// 안 하던 문제 방지.
    func refreshNow(forceOfficial: Bool = false) {
        workQueue.async { [weak self] in
            self?.tick()
            self?.fetchOfficial(minInterval: forceOfficial ? 5 : Self.officialRefreshThrottle)
        }
    }

    private func applyPollInterval(_ interval: TimeInterval) {
        pollInterval = interval
        lastTickAt = nil   // 간격이 바뀐 직후 지연 경고가 뜨지 않게
        jsonlTimer?.schedule(deadline: .now(), repeating: interval)
    }

    // MARK: - JSONL 틱

    /// 메인 스레드 소유 상태의 동기 스냅샷 (틱당 1회).
    private struct MainState {
        let officialEnabled: Bool
        let sessionLimit: Int
        let weeklyLimit: Int
        let weeklyStart: Date
        let weeklyResetEnabled: Bool
        let sensitivity: Thresholds.Sensitivity
        let limitAlertsEnabled: Bool
        let newSessionAlertEnabled: Bool
        let official: OfficialUsage?
    }

    private func mainState(now: Date) -> MainState {
        DispatchQueue.main.sync {
            MainState(officialEnabled: settings.officialEnabled,
                      sessionLimit: settings.estimatedSessionLimit,
                      weeklyLimit: settings.estimatedWeeklyLimit,
                      weeklyStart: settings.weeklyWindowStart(now: now),
                      weeklyResetEnabled: settings.weeklyResetEnabled,
                      sensitivity: settings.sensitivity,
                      limitAlertsEnabled: settings.limitAlertsEnabled,
                      newSessionAlertEnabled: settings.newSessionAlertEnabled,
                      official: official)
        }
    }

    private func tick() {
        let now = Date()
        // 틱 간격이 폴링 주기의 3배를 넘으면 타이머가 지연/정지된 것 — 진단 신호
        if let last = lastTickAt, now.timeIntervalSince(last) > pollInterval * 3 {
            log.warning("tick 지연: \(Int(now.timeIntervalSince(last)))초 만에 재개")
        }
        lastTickAt = now
        let main = mainState(now: now)

        // 유예 시간을 넘긴 공식 값은 버린다 (조회가 계속 실패하는 경우).
        let official = main.officialEnabled
            ? main.official.flatMap { now.timeIntervalSince($0.fetchedAt) < Self.officialGrace ? $0 : nil }
            : nil
        let officialExpired = main.officialEnabled && main.official != nil && official == nil

        if let reset = official?.weeklyResetsAt { knownWeeklyReset = reset }
        let nextWeeklyReset = knownWeeklyReset.map { WeeklyWindow.nextReset(from: $0, now: now) }
        // 공식 주간 창을 알면 그 창으로 집계해야 보간·자동 보정이 공식 %와 맞는다.
        let weeklyStart = nextWeeklyReset.map { $0.addingTimeInterval(-7 * 24 * 60 * 60) } ?? main.weeklyStart

        store.add(watcher.scan(now: now))
        let snap = store.snapshot(now: now, weeklySince: weeklyStart)
        if let version = snap.latestClientVersion { clientVersion = version }
        let rate = meter.update(tokensInLastMinute: snap.tokensLast60s)
        let idle = snap.lastEventDate.map { now.timeIntervalSince($0) } ?? .infinity
        let state = Thresholds.preset(sensitivity: main.sensitivity)
            .state(burnRate: rate, idleSeconds: idle)

        let sinceOfficial = official.map { store.tokens(since: $0.fetchedAt, now: now) } ?? 0
        let blockTokens = snap.currentBlock?.totalTokens ?? 0
        let session = GaugeMath.reading(officialBase: official?.sessionPercent, windowTokens: blockTokens,
                                        tokensSince: sinceOfficial, estimatedLimit: main.sessionLimit)
        let weekly = GaugeMath.reading(officialBase: official?.weeklyPercent, windowTokens: snap.weeklyTokens,
                                       tokensSince: sinceOfficial, estimatedLimit: main.weeklyLimit)
        let sessionRemaining = official?.sessionPercent
            .flatMap { GaugeMath.remainingTokens(base: $0, windowTokens: blockTokens, tokensSince: sinceOfficial) }
            ?? max(0, main.sessionLimit - blockTokens)
        let minutesLeft = GaugeMath.minutesUntilFull(remainingTokens: sessionRemaining, burnRate: rate)

        autoCalibrate(official: official, blockTokens: blockTokens, weeklyTokens: snap.weeklyTokens,
                      tokensSince: sinceOfficial)

        // 알림·오버라이드는 확정된 소스에서만: 공식 값 수신됨 or 연동 off(추정 모드 선택).
        // 연동 on인데 official==nil(시작 직후 미조회/일시 실패)이면 폴백 %가 순간 튀어
        // 오탐 알림·빨간 고양이가 나올 수 있으므로 평가를 보류한다.
        let authoritative = official != nil || !main.officialEnabled
        let level = authoritative
            ? UsageAlertLevel.level(percent: max(session.percent, weekly.percent))
            : .normal

        if main.limitAlertsEnabled && authoritative {
            fireLimitAlerts(main: main, official: official, snap: snap, nextWeeklyReset: nextWeeklyReset,
                            session: session, weekly: weekly, minutesLeft: minutesLeft)
        }
        checkNewBlock(snap: snap, enabled: main.newSessionAlertEnabled)

        log.debug("tick: today=\(snap.todayTokens) block=\(blockTokens) last60s=\(snap.tokensLast60s) rate=\(Int(rate)) state=\(state.rawValue, privacy: .public) 세션%=\(String(format: "%.1f", session.percent), privacy: .public)")

        let failure = lastOfficialFailure.isEmpty ? "공식 값이 오래됨" : lastOfficialFailure
        DispatchQueue.main.async {
            self.snapshot = snap
            self.burnRate = rate
            self.catState = state
            self.alertLevel = level
            self.sessionGauge = session
            self.weeklyGauge = weekly
            self.sessionMinutesLeft = minutesLeft
            self.nextWeeklyReset = nextWeeklyReset
            if !main.officialEnabled {
                self.official = nil   // 연동 off → 즉시 추정 모드
                self.officialStatus = .disabled
            } else if officialExpired {
                self.official = nil
                self.officialStatus = .failed(reason: failure)
            }
        }
    }

    /// 공식 조회 1건당 한 번, 그 시점의 로컬 토큰으로 한도를 역산해 둔다.
    private func autoCalibrate(official: OfficialUsage?, blockTokens: Int, weeklyTokens: Int, tokensSince: Int) {
        guard let official, official.fetchedAt != lastAutoCalibratedFetch else { return }
        lastAutoCalibratedFetch = official.fetchedAt
        let session = official.sessionPercent.flatMap {
            GaugeMath.impliedLimit(base: $0, windowTokens: blockTokens, tokensSince: tokensSince)
        }
        let weekly = official.weeklyPercent.flatMap {
            GaugeMath.impliedLimit(base: $0, windowTokens: weeklyTokens, tokensSince: tokensSince)
        }
        guard session != nil || weekly != nil else { return }
        DispatchQueue.main.async {
            if let session { self.settings.autoSessionLimit = session }
            if let weekly { self.settings.autoWeeklyLimit = weekly }
        }
    }

    // MARK: - 한도 알림 (§F4: 80%/95% 각 1회)

    private func fireLimitAlerts(main: MainState, official: OfficialUsage?, snap: UsageStore.Snapshot,
                                 nextWeeklyReset: Date?, session: GaugeReading, weekly: GaugeReading,
                                 minutesLeft: Int?) {
        // 창 식별자는 창이 유지되는 동안 바뀌지 않는 값이어야 한다.
        // now-7d처럼 매 틱 바뀌는 값을 쓰면 추적기가 리셋돼 알림이 다시 나간다.
        let sessionWindow = official?.sessionResetsAt.map { "\($0.timeIntervalSince1970)" }
            ?? snap.currentBlock.map { "\($0.start.timeIntervalSince1970)" } ?? "none"
        let weeklyWindow = nextWeeklyReset.map { "\($0.timeIntervalSince1970)" }
            ?? (main.weeklyResetEnabled ? "\(main.weeklyStart.timeIntervalSince1970)" : "rolling")

        for threshold in alertTracker.alertsToFire(kind: .session, percent: session.percent, windowId: sessionWindow) {
            notify(threshold: threshold, kind: "세션",
                   remaining: minutesLeft.map { "약 \(Format.minutes($0)) 분량 남음(현재 속도 기준)" })
        }
        for threshold in alertTracker.alertsToFire(kind: .weekly, percent: weekly.percent, windowId: weeklyWindow) {
            notify(threshold: threshold, kind: "주간", remaining: nil)
        }
    }

    private func notify(threshold: LimitAlertTracker.Threshold, kind: String, remaining: String?) {
        let emoji = threshold == .ninetyFive ? "⚠️" : "🥵"
        let title = "\(emoji) \(kind) 한도 \(threshold.rawValue)%"
        let body = remaining ?? "Claude Code /usage에서 정확한 잔여량을 확인하세요."
        DispatchQueue.main.async { Notifier.shared.send(title: title, body: body) }
    }

    /// 5시간 블록 리셋 감지 → "새 세션 시작!" (옵션, 기본 off).
    private func checkNewBlock(snap: UsageStore.Snapshot, enabled: Bool) {
        let start = snap.currentBlock?.start
        defer { lastBlockStart = start ?? lastBlockStart }
        guard enabled, let start, let previous = lastBlockStart, start != previous else { return }
        DispatchQueue.main.async {
            Notifier.shared.send(title: "🐱 새 세션 시작!", body: "5시간 사용량 창이 리셋되었습니다.")
        }
    }

    // MARK: - 공식 % 폴링 (180초)

    private func fetchOfficial(minInterval: TimeInterval) {
        let enabled = DispatchQueue.main.sync { settings.officialEnabled }
        guard enabled else {
            DispatchQueue.main.async {
                self.official = nil
                self.officialStatus = .disabled
            }
            return
        }
        let now = Date()
        // 키체인 프롬프트가 응답을 기다리는 동안 다음 폴링이 겹치지 않게 한다.
        guard !officialInFlight else { return }
        if let until = officialBackoffUntil, now < until { return }
        if minInterval > 0, let last = lastOfficialAttempt, now.timeIntervalSince(last) < minInterval { return }
        lastOfficialAttempt = now
        officialInFlight = true

        let version = clientVersion
        Task { [weak self] in
            guard let self else { return }
            let result: Result<OfficialUsage, Error>
            do {
                result = .success(try await self.provider.fetch(clientVersion: version))
            } catch {
                result = .failure(error)
            }
            self.workQueue.async { self.handleOfficial(result) }
        }
    }

    private func handleOfficial(_ result: Result<OfficialUsage, Error>) {
        officialInFlight = false
        switch result {
        case .success(let usage):
            officialBackoffUntil = nil
            log.info("공식 조회 성공: 세션 \(usage.sessionPercent ?? -1)% 주간 \(usage.weeklyPercent ?? -1)%")
            DispatchQueue.main.async {
                self.official = usage
                self.officialStatus = .live
            }
            tick()   // 메인 큐는 순서대로 돌므로 tick의 main.sync는 위 반영 뒤에 읽는다
        case .failure(let error):
            // 실패해도 앱은 죽지 않는다 (§8). 유예 시간 동안은 직전 값, 그 뒤로는 추정 모드.
            if case OAuthUsageProvider.ProviderError.http(429) = error {
                officialBackoffUntil = Date().addingTimeInterval(Self.rateLimitBackoff)
            }
            let reason = Self.describe(error)
            lastOfficialFailure = reason
            log.error("공식 조회 실패(\(reason, privacy: .public)): \(String(describing: error))")
            DispatchQueue.main.async {
                if let current = self.official,
                   Date().timeIntervalSince(current.fetchedAt) < Self.officialGrace {
                    self.officialStatus = .stale(reason: reason)
                } else {
                    self.official = nil
                    self.officialStatus = .failed(reason: reason)
                }
            }
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let error as OAuthUsageProvider.ProviderError:
            switch error {
            case .tokenNotFound: return "로그인 정보 없음"
            case .http(401), .http(403): return "인증 만료"
            case .http(429): return "요청 제한, 10분 뒤 재시도"
            case .http(let code): return "HTTP \(code)"
            case .badResponse: return "응답 형식이 바뀜"
            }
        case is URLError:
            return "네트워크 오류"
        default:
            return "알 수 없는 오류"
        }
    }
}

/// 상태는 workQueue 전용과 메인 스레드 전용으로 나뉘어 있고, 큐를 건널 때는 항상 async/sync로 넘긴다.
extension UsageEngine: @unchecked Sendable {}

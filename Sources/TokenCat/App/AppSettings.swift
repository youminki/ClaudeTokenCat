import Foundation
import Combine
import UsageCore

/// §F5 설정 (UserDefaults 저장). 변경 즉시 게이지에 반영되도록 ObservableObject.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    static let pollIntervalOptions: [Double] = [1, 3, 5, 10]

    private enum Key: String {
        case officialEnabled, plan, customSessionLimit
        case calibratedSessionLimit, calibratedWeeklyLimit
        case autoSessionLimit, autoWeeklyLimit
        case weeklyResetEnabled, weeklyResetWeekday, weeklyResetHour
        case sensitivity, pollInterval, limitAlertsEnabled, newSessionAlertEnabled, spriteTheme
        case menuBarLabel, runner, smoothness, tricksEnabled, customRunner
    }

    /// 추정 한도가 어디서 왔는지 (설정 화면 표시용).
    enum LimitSource {
        case manual, official, custom, preset

        var label: String {
            switch self {
            case .manual: return "직접 보정"
            case .official: return "공식 값으로 자동 보정"
            case .custom: return "직접 입력"
            case .preset: return "플랜 추정"
            }
        }
    }

    private let defaults = UserDefaults.standard

    /// 공식 사용량 연동 on/off (기본 on — off 또는 실패 시 추정 모드 폴백).
    @Published var officialEnabled: Bool { didSet { save(officialEnabled, .officialEnabled) } }

    /// 추정 모드용 플랜. 기본 pro — M0에서 이 계정 subscriptionType 실측 (docs/usage-endpoint.md).
    @Published var plan: Plan { didSet { save(plan.rawValue, .plan) } }

    /// Custom 플랜의 세션 한도 직접 입력값.
    @Published var customSessionLimit: Int { didSet { save(customSessionLimit, .customSessionLimit) } }

    /// `/usage` 캘리브레이션으로 역산된 한도 (0 = 없음).
    @Published var calibratedSessionLimit: Int { didSet { save(calibratedSessionLimit, .calibratedSessionLimit) } }
    @Published var calibratedWeeklyLimit: Int { didSet { save(calibratedWeeklyLimit, .calibratedWeeklyLimit) } }

    /// 공식 조회 성공 때마다 역산해 두는 한도 (0 = 없음). 조회가 실패해도 추정 게이지가 크게 어긋나지 않게 한다.
    @Published var autoSessionLimit: Int { didSet { save(autoSessionLimit, .autoSessionLimit) } }
    @Published var autoWeeklyLimit: Int { didSet { save(autoWeeklyLimit, .autoWeeklyLimit) } }

    /// 주간 리셋 수동 설정 (off면 롤링 7일).
    @Published var weeklyResetEnabled: Bool { didSet { save(weeklyResetEnabled, .weeklyResetEnabled) } }
    @Published var weeklyResetWeekday: Int { didSet { save(weeklyResetWeekday, .weeklyResetWeekday) } }  // 1=일 ... 7=토
    @Published var weeklyResetHour: Int { didSet { save(weeklyResetHour, .weeklyResetHour) } }

    @Published var sensitivity: Thresholds.Sensitivity { didSet { save(sensitivity.rawValue, .sensitivity) } }

    @Published var pollInterval: Double { didSet { save(pollInterval, .pollInterval) } }

    /// 80%/95% 한도 알림 (기본 on).
    @Published var limitAlertsEnabled: Bool { didSet { save(limitAlertsEnabled, .limitAlertsEnabled) } }

    /// 5시간 블록 리셋 알림 (§F4 — 기본 off).
    @Published var newSessionAlertEnabled: Bool { didSet { save(newSessionAlertEnabled, .newSessionAlertEnabled) } }

    /// 메뉴바 러너 종류와 색상 (색은 코드로 그린 러너에만 적용).
    @Published var runner: Runner { didSet { save(runner.rawValue, .runner) } }
    @Published var spriteTheme: SpriteTheme { didSet { save(spriteTheme.rawValue, .spriteTheme) } }

    /// 내 러너(사용자가 불러온 그림)나 개인 팩 러너를 쓰는 중이면 그 id. 기본 러너를 고르면 nil.
    @Published var customRunnerID: String? { didSet { save(customRunnerID ?? "", .customRunner) } }

    /// 지금 그릴 러너. 내 러너를 지웠거나 개인 팩이 없는 빌드면 기본 러너로 돌아간다.
    var character: RunnerCharacter {
        LocalPack.runner(storageID: customRunnerID)?.character
            ?? CustomRunnerStore.shared.runner(id: customRunnerID)?.character
            ?? runner.character
    }

    func select(_ pack: PackRunner) {
        customRunnerID = LocalPack.storageID(pack)
    }

    func select(_ runner: Runner) {
        customRunnerID = nil
        self.runner = runner
    }

    func select(_ custom: CustomRunner) {
        customRunnerID = custom.id
    }

    /// 메뉴바 애니메이션 fps 상한 (기본 30fps).
    @Published var smoothness: SpriteSmoothness { didSet { save(smoothness.rawValue, .smoothness) } }

    /// 가끔 혼자 장난치기 (점프, 하트, 춤 등). 끄면 상태가 바뀔 때만 움직임이 달라진다.
    @Published var tricksEnabled: Bool { didSet { save(tricksEnabled, .tricksEnabled) } }

    /// 메뉴바 고양이 옆에 띄울 사용률 (기본 끔).
    @Published var menuBarLabel: MenuBarLabel { didSet { save(menuBarLabel.rawValue, .menuBarLabel) } }

    /// 로그인 시 자동 시작 (SMAppService, 번들 앱에서만 동작). 시스템 상태가 원본이라 저장하지 않는다.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do { try LaunchAtLogin.set(launchAtLogin) }
            catch { launchAtLogin = oldValue }   // 실패 시 토글 원복
        }
    }

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: Key, _ fallback: Bool) -> Bool { d.object(forKey: key.rawValue) as? Bool ?? fallback }
        func int(_ key: Key, _ fallback: Int = 0) -> Int { d.object(forKey: key.rawValue) as? Int ?? fallback }
        func string(_ key: Key) -> String { d.string(forKey: key.rawValue) ?? "" }

        officialEnabled = bool(.officialEnabled, true)
        plan = Plan(rawValue: string(.plan)) ?? .pro
        customSessionLimit = int(.customSessionLimit)
        calibratedSessionLimit = int(.calibratedSessionLimit)
        calibratedWeeklyLimit = int(.calibratedWeeklyLimit)
        autoSessionLimit = int(.autoSessionLimit)
        autoWeeklyLimit = int(.autoWeeklyLimit)
        weeklyResetEnabled = bool(.weeklyResetEnabled, false)
        weeklyResetWeekday = int(.weeklyResetWeekday, 1)
        weeklyResetHour = int(.weeklyResetHour, 9)
        sensitivity = Thresholds.Sensitivity(rawValue: string(.sensitivity)) ?? .normal
        let poll = d.double(forKey: Key.pollInterval.rawValue)
        pollInterval = poll > 0 ? poll : 3.0
        limitAlertsEnabled = bool(.limitAlertsEnabled, true)
        newSessionAlertEnabled = bool(.newSessionAlertEnabled, false)
        runner = Runner(rawValue: string(.runner)) ?? .cat
        spriteTheme = SpriteTheme(rawValue: string(.spriteTheme)) ?? .auto
        // 내 러너 목록에서 사라진 id는 버린다 (그대로 두면 메뉴·고르기에서 아무 것도 선택되지 않아 보인다)
        let savedCustom = string(.customRunner)
        let known = CustomRunnerStore.shared.runner(id: savedCustom) != nil || LocalPack.runner(storageID: savedCustom) != nil
        customRunnerID = known ? savedCustom : nil
        smoothness = SpriteSmoothness(rawValue: string(.smoothness)) ?? .smooth
        tricksEnabled = bool(.tricksEnabled, true)
        menuBarLabel = MenuBarLabel(rawValue: string(.menuBarLabel)) ?? .off
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: 파생값

    /// 보정값 우선순위: 사용자가 직접 넣은 값 > 공식 조회로 역산한 값.
    private var sessionCalibration: Int? {
        calibratedSessionLimit > 0 ? calibratedSessionLimit : (autoSessionLimit > 0 ? autoSessionLimit : nil)
    }

    private var weeklyCalibration: Int? {
        calibratedWeeklyLimit > 0 ? calibratedWeeklyLimit : (autoWeeklyLimit > 0 ? autoWeeklyLimit : nil)
    }

    /// 추정 세션 한도 (보정 > custom > 프리셋).
    var estimatedSessionLimit: Int {
        PlanLimits.sessionLimit(plan: plan,
                                customLimit: customSessionLimit > 0 ? customSessionLimit : nil,
                                calibratedLimit: sessionCalibration)
    }

    var estimatedWeeklyLimit: Int {
        PlanLimits.weeklyLimit(sessionLimit: estimatedSessionLimit, calibratedLimit: weeklyCalibration)
    }

    var sessionLimitSource: LimitSource {
        if calibratedSessionLimit > 0 { return .manual }
        if autoSessionLimit > 0 { return .official }
        return plan == .custom && customSessionLimit > 0 ? .custom : .preset
    }

    var weeklyLimitSource: LimitSource {
        if calibratedWeeklyLimit > 0 { return .manual }
        if autoWeeklyLimit > 0 { return .official }
        return sessionLimitSource
    }
}

/// 메뉴바 고양이 옆 사용률 표시.
enum MenuBarLabel: String, CaseIterable {
    case off, session, weekly, higher

    var displayName: String {
        switch self {
        case .off: return "끔"
        case .session: return "세션"
        case .weekly: return "주간"
        case .higher: return "높은 쪽"
        }
    }
}

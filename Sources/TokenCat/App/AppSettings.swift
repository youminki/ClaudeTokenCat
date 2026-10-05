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

    /// 러너 색상 테마 (v1.1 — 고양이 1종 + 색상 3종, 코드 생성 스프라이트에만 적용).
    @Published var spriteTheme: SpriteTheme { didSet { save(spriteTheme.rawValue, .spriteTheme) } }

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
        spriteTheme = SpriteTheme(rawValue: string(.spriteTheme)) ?? .auto
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

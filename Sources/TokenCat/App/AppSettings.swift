import Foundation
import Combine
import UsageCore

/// §F5 설정 (UserDefaults 저장). 변경 즉시 게이지에 반영되도록 ObservableObject.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    /// 공식 사용량 연동 on/off (기본 on — off 또는 실패 시 추정 모드 폴백).
    @Published var officialEnabled: Bool {
        didSet { defaults.set(officialEnabled, forKey: "officialEnabled") }
    }

    /// 추정 모드용 플랜. 기본 pro — M0에서 이 계정 subscriptionType 실측 (docs/usage-endpoint.md).
    @Published var plan: Plan {
        didSet { defaults.set(plan.rawValue, forKey: "plan") }
    }

    /// Custom 플랜의 세션 한도 직접 입력값.
    @Published var customSessionLimit: Int {
        didSet { defaults.set(customSessionLimit, forKey: "customSessionLimit") }
    }

    /// `/usage` 캘리브레이션으로 역산된 한도 (0 = 없음).
    @Published var calibratedSessionLimit: Int {
        didSet { defaults.set(calibratedSessionLimit, forKey: "calibratedSessionLimit") }
    }

    /// 주간 캘리브레이션 한도 (0 = 없음 → 세션 한도 × 8).
    @Published var calibratedWeeklyLimit: Int {
        didSet { defaults.set(calibratedWeeklyLimit, forKey: "calibratedWeeklyLimit") }
    }

    /// 주간 리셋 수동 설정 (off면 롤링 7일).
    @Published var weeklyResetEnabled: Bool {
        didSet { defaults.set(weeklyResetEnabled, forKey: "weeklyResetEnabled") }
    }
    @Published var weeklyResetWeekday: Int {  // 1=일 ... 7=토
        didSet { defaults.set(weeklyResetWeekday, forKey: "weeklyResetWeekday") }
    }
    @Published var weeklyResetHour: Int {
        didSet { defaults.set(weeklyResetHour, forKey: "weeklyResetHour") }
    }

    @Published var sensitivity: Thresholds.Sensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: "sensitivity") }
    }

    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: "pollInterval") }
    }

    /// 80%/95% 한도 알림 (기본 on).
    @Published var limitAlertsEnabled: Bool {
        didSet { defaults.set(limitAlertsEnabled, forKey: "limitAlertsEnabled") }
    }

    /// 5시간 블록 리셋 알림 (§F4 — 기본 off).
    @Published var newSessionAlertEnabled: Bool {
        didSet { defaults.set(newSessionAlertEnabled, forKey: "newSessionAlertEnabled") }
    }

    /// 러너 색상 테마 (v1.1 — 고양이 1종 + 색상 3종, 코드 생성 스프라이트에만 적용).
    @Published var spriteTheme: SpriteTheme {
        didSet { defaults.set(spriteTheme.rawValue, forKey: "spriteTheme") }
    }

    /// 로그인 시 자동 시작 (SMAppService — 번들 앱에서만 동작).
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do { try LaunchAtLogin.set(launchAtLogin) }
            catch { launchAtLogin = oldValue }   // 실패 시 토글 원복
        }
    }

    private init() {
        officialEnabled = defaults.object(forKey: "officialEnabled") as? Bool ?? true
        plan = Plan(rawValue: defaults.string(forKey: "plan") ?? "") ?? .pro
        customSessionLimit = defaults.integer(forKey: "customSessionLimit")
        calibratedSessionLimit = defaults.integer(forKey: "calibratedSessionLimit")
        calibratedWeeklyLimit = defaults.integer(forKey: "calibratedWeeklyLimit")
        weeklyResetEnabled = defaults.bool(forKey: "weeklyResetEnabled")
        weeklyResetWeekday = defaults.object(forKey: "weeklyResetWeekday") as? Int ?? 1
        weeklyResetHour = defaults.object(forKey: "weeklyResetHour") as? Int ?? 9
        sensitivity = Thresholds.Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .normal
        let p = defaults.double(forKey: "pollInterval")
        pollInterval = p > 0 ? p : 3.0
        limitAlertsEnabled = defaults.object(forKey: "limitAlertsEnabled") as? Bool ?? true
        newSessionAlertEnabled = defaults.bool(forKey: "newSessionAlertEnabled")
        spriteTheme = SpriteTheme(rawValue: defaults.string(forKey: "spriteTheme") ?? "") ?? .auto
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: 파생값

    /// 추정 세션 한도 (캘리브레이션 > custom > 프리셋).
    var estimatedSessionLimit: Int {
        PlanLimits.sessionLimit(
            plan: plan,
            customLimit: customSessionLimit > 0 ? customSessionLimit : nil,
            calibratedLimit: calibratedSessionLimit > 0 ? calibratedSessionLimit : nil)
    }

    var estimatedWeeklyLimit: Int {
        PlanLimits.weeklyLimit(sessionLimit: estimatedSessionLimit,
                               calibratedLimit: calibratedWeeklyLimit > 0 ? calibratedWeeklyLimit : nil)
    }

    /// 주간 창 시작 (사용자 리셋 or 롤링 7일).
    func weeklyWindowStart(now: Date = Date()) -> Date {
        weeklyResetEnabled
            ? WeeklyWindow.lastReset(weekday: weeklyResetWeekday, hour: weeklyResetHour, now: now)
            : WeeklyWindow.rollingStart(now: now)
    }
}

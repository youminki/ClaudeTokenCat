import Foundation
import Combine
import UsageCore

/// §F5 설정 (UserDefaults 저장). 변경 즉시 게이지에 반영되도록 ObservableObject.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    static let pollIntervalOptions: [Double] = [1, 3, 5, 10]

    private enum Key: String {
        case officialEnabled, sensitivity, pollInterval, limitAlertsEnabled, newSessionAlertEnabled, spriteTheme
        case menuBarLabel, runner, smoothness, tricksEnabled, customRunner, runnerSize
    }

    private let defaults = UserDefaults.standard

    /// 공식 사용량 연동 on/off (기본 on). 끄면 세션·주간 게이지를 비우고 로컬 통계만 보인다.
    @Published var officialEnabled: Bool { didSet { save(officialEnabled, .officialEnabled) } }

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

    /// 메뉴바 러너 크기 (기본 크게).
    @Published var runnerSize: RunnerSize { didSet { save(runnerSize.rawValue, .runnerSize) } }

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
        func string(_ key: Key) -> String { d.string(forKey: key.rawValue) ?? "" }

        officialEnabled = bool(.officialEnabled, true)
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
        runnerSize = RunnerSize(rawValue: string(.runnerSize)) ?? .large
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
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

/// 메뉴바 러너 크기. 메뉴바 높이가 정해져 있어, 크게·최대는 머리 쪽을 기준으로 확대하고 발끝을 잘라 얼굴을 키운다.
enum RunnerSize: String, CaseIterable {
    case full, large, max

    var displayName: String {
        switch self {
        case .full: return "전신"
        case .large: return "크게"
        case .max: return "최대"
        }
    }

    var zoom: CGFloat {
        switch self {
        case .full: return 1
        case .large: return 1.3
        case .max: return 1.6
        }
    }
}

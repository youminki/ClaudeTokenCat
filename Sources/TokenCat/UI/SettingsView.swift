import SwiftUI
import UsageCore

/// §F5 설정. 변경은 UserDefaults에 즉시 저장되고 게이지에 바로 반영된다.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: UsageEngine

    @StateObject private var form = CalibrationForm()

    private enum CalibrationTarget { case session, weekly }

    var body: some View {
        Form {
            Section("데이터 소스") {
                Toggle("공식 사용량 연동 (Anthropic 계정 기준)", isOn: $settings.officialEnabled)
                LabeledContent("상태") {
                    Text(officialStatusText).foregroundStyle(officialStatusColor)
                }
                Text("끄거나 조회에 실패하면 아래 추정 한도로 계산합니다. 공식 조회가 성공할 때마다 추정 한도도 자동으로 맞춰집니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("추정 모드 플랜") {
                Picker("플랜", selection: $settings.plan) {
                    ForEach(Plan.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if settings.plan == .custom {
                    TextField("세션 한도 (tokens)", value: $settings.customSessionLimit, format: .number)
                }
                LabeledContent("추정 세션 한도",
                               value: "\(Format.tokens(settings.estimatedSessionLimit)) (\(settings.sessionLimitSource.label))")
                LabeledContent("추정 주간 한도",
                               value: "\(Format.tokens(settings.estimatedWeeklyLimit)) (\(settings.weeklyLimitSource.label))")
            }

            Section("한도 보정 (추정 모드)") {
                Text("Claude Code /usage에 보이는 %를 입력하면 추정 한도를 역산합니다. 직접 넣은 값이 공식 자동 보정보다 우선합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                calibrationRow("세션 % (예: 61)", text: $form.sessionInput, target: .session)
                calibrationRow("주간 % (예: 42)", text: $form.weeklyInput, target: .weekly)
                if settings.calibratedSessionLimit > 0 || settings.calibratedWeeklyLimit > 0 {
                    HStack {
                        Text([
                            settings.calibratedSessionLimit > 0
                                ? "세션 \(Format.tokens(settings.calibratedSessionLimit))" : nil,
                            settings.calibratedWeeklyLimit > 0
                                ? "주간 \(Format.tokens(settings.calibratedWeeklyLimit))" : nil,
                        ].compactMap { $0 }.joined(separator: " · ") + " (직접 보정)")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("초기화") {
                            settings.calibratedSessionLimit = 0
                            settings.calibratedWeeklyLimit = 0
                            form.message = nil
                        }
                        .controlSize(.mini)
                    }
                }
                if let message = form.message {
                    Text(message).font(.caption)
                        .foregroundStyle(form.messageIsError ? .orange : .green)
                }
            }

            Section("주간 초기화 (추정 모드)") {
                Toggle("초기화 요일·시각 직접 지정 (끄면 최근 7일)", isOn: $settings.weeklyResetEnabled)
                if settings.weeklyResetEnabled {
                    Picker("요일", selection: $settings.weeklyResetWeekday) {
                        ForEach(1...7, id: \.self) { Text(Format.weekdayName($0)).tag($0) }
                    }
                    Picker("시각", selection: $settings.weeklyResetHour) {
                        ForEach(0..<24, id: \.self) { Text(Format.hour($0)).tag($0) }
                    }
                }
                if engine.nextWeeklyReset != nil {
                    Text("공식 응답에서 초기화 시각을 알면 그 값을 먼저 씁니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("알림") {
                Toggle("한도 임박 알림 (80% / 95%, 각 1회)", isOn: $settings.limitAlertsEnabled)
                Toggle("세션 초기화 알림 (5시간)", isOn: $settings.newSessionAlertEnabled)
                if !Notifier.shared.available {
                    Text("알림은 빌드된 TokenCat.app에서만 동작합니다 (swift run 개발 실행 제외).")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("일반") {
                Toggle("로그인 시 자동 시작", isOn: $settings.launchAtLogin)
                    .disabled(!LaunchAtLogin.available)
                if !LaunchAtLogin.available {
                    Text("자동 시작은 빌드된 TokenCat.app에서만 설정할 수 있습니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("로컬 기록 확인 주기", selection: $settings.pollInterval) {
                    ForEach(AppSettings.pollIntervalOptions, id: \.self) {
                        Text(String(format: "%.0f초", $0)).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("러너") {
                RunnerPicker(settings: settings)
                Picker("색상", selection: $settings.spriteTheme) {
                    ForEach(SpriteTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("움직임", selection: $settings.smoothness) {
                    ForEach(SpriteSmoothness.allCases, id: \.self) {
                        Text("\($0.displayName) (\(Int($0.fps))fps)").tag($0)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("가끔 혼자 장난치기 (점프, 하트, 춤 등)", isOn: $settings.tricksEnabled)
                Picker("메뉴바 사용률", selection: $settings.menuBarLabel) {
                    ForEach(MenuBarLabel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("민감도", selection: $settings.sensitivity) {
                    ForEach(Thresholds.Sensitivity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("민감도가 높을수록 적은 사용량에도 빨리 달립니다. 메뉴바 사용률 앞의 ~는 추정값입니다. 움직임을 높이면 더 매끄럽지만 CPU를 조금 더 씁니다. '본래 색'은 메뉴바에서도 캐릭터 고유색으로 그립니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("정보") {
                LabeledContent("버전", value: Self.versionText)
                LabeledContent("데이터 폴더") {
                    Button("Finder에서 열기") { NSWorkspace.shared.open(Self.projectsDirectory) }
                        .controlSize(.small)
                }
                .help(Self.projectsDirectory.path)
                Link("GitHub 저장소", destination: URL(string: "https://github.com/youminki/ClaudeTokenCat")!)
            }
        }
        .formStyle(.grouped)   // 내용이 넘치면 Form이 스스로 스크롤
        .frame(width: 440)
        .frame(minHeight: 340, idealHeight: 520, maxHeight: 720)
    }

    private static let projectsDirectory = ClaudePaths.configDirectory.appendingPathComponent("projects")

    /// install.sh로 설치한 빌드가 어느 커밋인지 (build-app.sh가 Info.plist에 남긴다).
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "개발 실행" }
        return (info?["TokenCatCommit"] as? String).map { "\(version) (\($0))" } ?? version
    }

    private var officialStatusText: String {
        switch engine.officialStatus {
        case .live:
            let age = engine.official.map { Int(Date().timeIntervalSince($0.fetchedAt) / 60) } ?? 0
            return age < 1 ? "연동 중 (방금 조회)" : "연동 중 (\(age)분 전 조회)"
        case .waiting: return "조회 중…"
        case .stale(let reason): return "조회 실패, 직전 값 사용 중 (\(reason))"
        case .failed(let reason): return "조회 실패, 추정 모드 (\(reason))"
        case .disabled: return "꺼짐"
        }
    }

    private var officialStatusColor: Color {
        switch engine.officialStatus {
        case .live: return .green
        case .waiting, .disabled: return .secondary
        case .stale, .failed: return .orange
        }
    }

    private func calibrationRow(_ placeholder: String, text: Binding<String>, target: CalibrationTarget) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .onSubmit { calibrate(target) }
            Button("보정") { calibrate(target) }
        }
    }

    /// "61%", " 61 " 같은 입력도 허용.
    private func parsePercent(_ input: String) -> Double? {
        Double(input.filter { $0.isNumber || $0 == "." })
    }

    private func calibrate(_ target: CalibrationTarget) {
        let input = target == .session ? form.sessionInput : form.weeklyInput
        guard let percent = parsePercent(input) else {
            showCalibration(error: "숫자를 입력해주세요 (예: \(target == .session ? 61 : 42))")
            return
        }
        let tokens = target == .session
            ? engine.snapshot?.currentBlock?.totalTokens ?? 0
            : engine.snapshot?.weeklyTokens ?? 0
        guard let limit = PlanLimits.calibratedLimit(windowTokens: tokens, usagePercent: percent) else {
            if tokens == 0 {
                showCalibration(error: target == .session
                    ? "활성 세션이 없어 보정할 수 없습니다. Claude Code 사용 직후 시도해주세요."
                    : "주간 사용 기록이 없어 보정할 수 없습니다.")
            } else {
                showCalibration(error: "%는 0 초과 100 이하로 입력해주세요.")
            }
            return
        }
        switch target {
        case .session:
            settings.calibratedSessionLimit = limit
            form.sessionInput = ""
            showCalibration(success: "세션 한도 보정됨: \(Format.tokens(limit)) (추정)")
        case .weekly:
            settings.calibratedWeeklyLimit = limit
            form.weeklyInput = ""
            showCalibration(success: "주간 한도 보정됨: \(Format.tokens(limit)) (추정)")
        }
    }

    private func showCalibration(success: String? = nil, error: String? = nil) {
        form.message = success ?? error
        form.messageIsError = (error != nil)
    }
}

/// macOS 27 SDK의 `@State`는 매크로라 Command Line Tools만으로는 빌드되지 않는다.
/// install.sh가 Xcode 없이도 돌도록 입력 상태를 ObservableObject로 둔다.
final class CalibrationForm: ObservableObject {
    @Published var sessionInput = ""
    @Published var weeklyInput = ""
    @Published var message: String?
    @Published var messageIsError = false
}

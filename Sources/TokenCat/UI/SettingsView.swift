import SwiftUI
import UsageCore

/// §F5 설정. 변경은 UserDefaults에 즉시 저장되고 게이지에 바로 반영된다.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: UsageEngine

    @State private var sessionCalibrationInput = ""
    @State private var weeklyCalibrationInput = ""
    @State private var calibrationMessage: String?
    @State private var calibrationMessageIsError = false

    var body: some View {
        Form {
            Section("데이터 소스") {
                Toggle("공식 사용량 연동 (Anthropic 계정 기준)", isOn: $settings.officialEnabled)
                Text("끄거나 조회에 실패하면 아래 플랜 기반 추정 모드로 폴백합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("추정 모드 플랜") {
                Picker("플랜", selection: $settings.plan) {
                    ForEach(Plan.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if settings.plan == .custom {
                    TextField("세션 한도 (tokens)", value: $settings.customSessionLimit, format: .number)
                }
                LabeledContent("추정 세션 한도", value: Format.tokens(settings.estimatedSessionLimit) + " (추정)")
                LabeledContent("추정 주간 한도", value: Format.tokens(settings.estimatedWeeklyLimit) + " (추정)")
            }

            Section("한도 캘리브레이션 (추정 모드용)") {
                Text("Claude Code /usage에 보이는 %를 입력하면 추정 한도를 역산합니다. 공식 연동이 켜져 있는 동안 게이지는 공식 %를 그대로 쓰므로, 이 값은 연동을 끄거나 조회에 실패했을 때 사용됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("세션 % (예: 61)", text: $sessionCalibrationInput)
                        .onSubmit { calibrateSession() }
                    Button("보정") { calibrateSession() }
                }
                HStack {
                    TextField("주간 % (예: 42)", text: $weeklyCalibrationInput)
                        .onSubmit { calibrateWeekly() }
                    Button("보정") { calibrateWeekly() }
                }
                if settings.calibratedSessionLimit > 0 || settings.calibratedWeeklyLimit > 0 {
                    HStack {
                        Text([
                            settings.calibratedSessionLimit > 0
                                ? "세션 \(Format.tokens(settings.calibratedSessionLimit))" : nil,
                            settings.calibratedWeeklyLimit > 0
                                ? "주간 \(Format.tokens(settings.calibratedWeeklyLimit))" : nil,
                        ].compactMap { $0 }.joined(separator: " · ") + " (보정됨)")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("초기화") {
                            settings.calibratedSessionLimit = 0
                            settings.calibratedWeeklyLimit = 0
                            calibrationMessage = nil
                        }
                        .controlSize(.mini)
                    }
                }
                if let message = calibrationMessage {
                    Text(message).font(.caption)
                        .foregroundStyle(calibrationMessageIsError ? .orange : .green)
                }
            }

            Section("주간 리셋 (추정 모드용)") {
                Toggle("리셋 요일·시각 수동 설정 (off면 롤링 7일)", isOn: $settings.weeklyResetEnabled)
                if settings.weeklyResetEnabled {
                    Picker("요일", selection: $settings.weeklyResetWeekday) {
                        ForEach(1...7, id: \.self) { Text(Format.weekdayName($0)).tag($0) }
                    }
                    Picker("시각", selection: $settings.weeklyResetHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                }
            }

            Section("알림") {
                Toggle("한도 임박 알림 (80% / 95%, 각 1회)", isOn: $settings.limitAlertsEnabled)
                Toggle("새 세션 시작 알림 (5시간 창 리셋)", isOn: $settings.newSessionAlertEnabled)
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
            }

            Section("러너") {
                Picker("색상 테마", selection: $settings.spriteTheme) {
                    ForEach(SpriteTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("민감도", selection: $settings.sensitivity) {
                    Text("낮음").tag(Thresholds.Sensitivity.low)
                    Text("보통").tag(Thresholds.Sensitivity.normal)
                    Text("높음").tag(Thresholds.Sensitivity.high)
                }
                .pickerStyle(.segmented)
                LabeledContent("폴링 주기", value: String(format: "%.0f초", settings.pollInterval))
                Text("폴링 주기 변경은 앱 재시작 후 적용됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)   // 내용이 넘치면 Form이 스스로 스크롤
        .frame(width: 400)
        .frame(minHeight: 340, idealHeight: 460, maxHeight: 600)
    }

    /// "61%", " 61 " 같은 입력도 허용.
    private func parsePercent(_ input: String) -> Double? {
        Double(input.filter { $0.isNumber || $0 == "." })
    }

    private func calibrateSession() {
        guard let percent = parsePercent(sessionCalibrationInput) else {
            showCalibration(error: "숫자를 입력해주세요 (예: 61)")
            return
        }
        let blockTokens = engine.snapshot?.currentBlock?.totalTokens ?? 0
        if let limit = PlanLimits.calibratedLimit(windowTokens: blockTokens, usagePercent: percent) {
            settings.calibratedSessionLimit = limit
            sessionCalibrationInput = ""
            showCalibration(success: "세션 한도 보정됨: \(Format.tokens(limit)) (추정)")
        } else {
            showCalibration(error: blockTokens == 0
                ? "활성 세션이 없어 보정할 수 없습니다 — Claude Code 사용 직후 시도해주세요."
                : "%는 0 초과 100 이하로 입력해주세요.")
        }
    }

    private func calibrateWeekly() {
        guard let percent = parsePercent(weeklyCalibrationInput) else {
            showCalibration(error: "숫자를 입력해주세요 (예: 42)")
            return
        }
        let weeklyTokens = engine.snapshot?.weeklyTokens ?? 0
        if let limit = PlanLimits.calibratedLimit(windowTokens: weeklyTokens, usagePercent: percent) {
            settings.calibratedWeeklyLimit = limit
            weeklyCalibrationInput = ""
            showCalibration(success: "주간 한도 보정됨: \(Format.tokens(limit)) (추정)")
        } else {
            showCalibration(error: weeklyTokens == 0
                ? "주간 사용 기록이 없어 보정할 수 없습니다."
                : "%는 0 초과 100 이하로 입력해주세요.")
        }
    }

    private func showCalibration(success: String? = nil, error: String? = nil) {
        calibrationMessage = success ?? error
        calibrationMessageIsError = (error != nil)
    }
}

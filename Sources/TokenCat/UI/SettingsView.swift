import SwiftUI
import UsageCore

/// §F5 설정. 변경은 UserDefaults에 즉시 저장되고 게이지에 바로 반영된다.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: UsageEngine

    var body: some View {
        Form {
            Section("데이터 소스") {
                Toggle("공식 사용량 연동 (Anthropic 계정 기준)", isOn: $settings.officialEnabled)
                LabeledContent("상태") {
                    Text(officialStatusText).foregroundStyle(officialStatusColor)
                }
                Text("세션·주간 사용률은 공식 값만 씁니다. 끄거나 조회에 실패하면 비워 두고, 속도와 오늘 사용량은 로컬 기록으로 계속 보여 줍니다.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Text("민감도가 높을수록 적은 사용량에도 빨리 달립니다. 움직임을 높이면 더 매끄럽지만 CPU를 조금 더 씁니다. '본래 색'은 메뉴바에서도 캐릭터 고유색으로 그립니다.")
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
        case .failed(let reason): return "조회 실패 (\(reason))"
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
}

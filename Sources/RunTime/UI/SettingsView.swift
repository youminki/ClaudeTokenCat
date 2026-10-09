import SwiftUI
import UsageCore

/// 설정 창. 일반·러너·사용량 탭으로 나눠, 러너 격자가 다른 설정을 밀어내지 않게 한다.
/// 변경은 UserDefaults에 바로 저장되고 메뉴바와 팝오버에 바로 반영된다.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: UsageEngine
    @StateObject private var tab: SettingsTabState

    enum Tab: Hashable { case general, runner, usage }

    init(settings: AppSettings, engine: UsageEngine, initialTab: Tab = .general) {
        self.settings = settings
        self.engine = engine
        _tab = StateObject(wrappedValue: SettingsTabState(initialTab))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("설정 구역", selection: $tab.selection) {
                Text("일반").tag(Tab.general)
                Text("러너").tag(Tab.runner)
                Text("사용량").tag(Tab.usage)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            switch tab.selection {
            case .general: general
            case .runner: runner
            case .usage: usage
            }
        }
        .frame(width: 480)
        .frame(minHeight: 420, idealHeight: 560, maxHeight: 760)
    }

    // MARK: 일반

    private var general: some View {
        Form {
            Section {
                DetailToggle("로그인 시 자동 시작", detail: "Mac에 로그인하면 메뉴바에 러너를 띄웁니다.", isOn: $settings.launchAtLogin)
                    .disabled(!LaunchAtLogin.available)
                if !LaunchAtLogin.available {
                    devOnlyNote("자동 시작")
                }
                Picker(selection: $settings.menuBarLabel) {
                    ForEach(MenuBarLabel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    DetailLabel("메뉴바 사용률", detail: "러너 옆에 사용률을 숫자로 함께 보여 줍니다.")
                }
                .pickerStyle(.segmented)
            }
            Section("업데이트") {
                UpdateRow(updater: AppUpdater.shared)
            }
            Section("정보") {
                LabeledContent("버전", value: Self.versionText)
                LabeledContent {
                    Button("Finder에서 열기") { NSWorkspace.shared.open(Self.projectsDirectory) }
                        .controlSize(.small)
                } label: {
                    DetailLabel("Claude Code 기록 폴더", detail: "속도와 오늘 사용량을 세는 원본입니다.")
                }
                .help(Self.projectsDirectory.path)
                Link(destination: URL(string: "https://github.com/youminki/RunTime")!) {
                    Label("GitHub 저장소", systemImage: "arrow.up.right.square")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 러너

    private var runner: some View {
        Form {
            Section {
                RunnerPicker(settings: settings)
            }
            Section("모습") {
                Picker(selection: $settings.runnerSize) {
                    ForEach(RunnerSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    DetailLabel("메뉴바 크기", detail: "'크게'를 고르면 머리 위 여백을 줄여 캐릭터를 키우고 메뉴바 칸이 조금 넓어집니다.")
                }
                .pickerStyle(.segmented)
                Picker(selection: $settings.spriteTheme) {
                    ForEach(SpriteTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    DetailLabel("색상", detail: "'본래 색'을 고르면 메뉴바에서도 캐릭터 고유색으로 그립니다.")
                }
                Picker(selection: $settings.smoothness) {
                    ForEach(SpriteSmoothness.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    DetailLabel("움직임", detail: "\(settings.smoothness.displayName): 초당 \(Int(settings.smoothness.fps))장. 장 수가 많을수록 매끄럽지만 CPU를 조금 더 씁니다.")
                }
                .pickerStyle(.segmented)
                DetailToggle("가끔 혼자 장난치기", detail: "점프, 하트, 춤 같은 동작을 가끔 합니다.", isOn: $settings.tricksEnabled)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 사용량

    private var usage: some View {
        Form {
            Section("공식 사용량") {
                DetailToggle("공식 사용량 연동", detail: "Anthropic 계정 기준 사용률을 3분마다 받습니다. 끄거나 받지 못하면 사용률은 비워 두고, 속도와 오늘 사용량은 로컬 기록으로 계속 보여 줍니다.",
                             isOn: $settings.officialEnabled)
                LabeledContent("상태") {
                    HStack(spacing: 6) {
                        Circle().fill(officialStatusColor).frame(width: 7, height: 7)
                        Text(officialStatusText).foregroundStyle(.secondary)
                    }
                }
            }
            Section("속도") {
                Picker(selection: $settings.sensitivity) {
                    ForEach(Thresholds.Sensitivity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    DetailLabel("민감도", detail: "높을수록 적은 사용량에도 빨리 달립니다.")
                }
                .pickerStyle(.segmented)
                Picker(selection: $settings.pollInterval) {
                    ForEach(AppSettings.pollIntervalOptions, id: \.self) {
                        Text(String(format: "%.0f초", $0)).tag($0)
                    }
                } label: {
                    DetailLabel("기록 확인 주기", detail: "짧을수록 러너가 빨리 반응합니다.")
                }
                .pickerStyle(.segmented)
            }
            Section("알림") {
                DetailToggle("한도 임박 알림", detail: "세션·주간 사용률이 80%, 95%에 닿으면 한 번씩 알립니다.",
                             isOn: $settings.limitAlertsEnabled)
                DetailToggle("세션 초기화 알림", detail: "5시간 창이 새로 시작되면 알립니다.", isOn: $settings.newSessionAlertEnabled)
                if !Notifier.shared.available {
                    devOnlyNote("알림")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func devOnlyNote(_ feature: String) -> some View {
        Text("\(feature)은 install.sh로 설치한 RunTime.app에서만 동작합니다.")
            .font(.caption).foregroundStyle(.orange)
    }

    private static let projectsDirectory = ClaudePaths.configDirectory.appendingPathComponent("projects")

    /// install.sh로 설치한 빌드가 어느 커밋인지 (build-app.sh가 Info.plist에 남긴다).
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "개발 실행" }
        return (info?["RunTimeCommit"] as? String).map { "\(version) (\($0))" } ?? version
    }

    private var officialStatusText: String {
        switch engine.officialStatus {
        case .live:
            let age = engine.official.map { Int(Date().timeIntervalSince($0.fetchedAt) / 60) } ?? 0
            return age < 1 ? "연동 중 · 방금 받음" : "연동 중 · \(age)분 전 받음"
        case .waiting: return "조회 중…"
        case .stale(let reason): return "직전 값 사용 중 · \(reason)"
        case .failed(let reason): return "받지 못함 · \(reason)"
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

/// 설정 > 정보의 업데이트 줄. 새 커밋이 있으면 단추 하나로 받아 다시 빌드한다.
private struct UpdateRow: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        LabeledContent("상태") {
            HStack(spacing: 8) {
                Text(status).foregroundStyle(statusColor).lineLimit(2).multilineTextAlignment(.trailing)
                switch updater.state {
                case .available:
                    Button("지금 업데이트") { updater.update() }.controlSize(.small)
                case .checking, .updating:
                    ProgressView().controlSize(.small)
                case .unavailable:
                    EmptyView()
                default:
                    Button("확인") { updater.check() }.controlSize(.small)
                }
            }
        }
        if updater.canCheck {
            DetailToggle("자동으로 업데이트", detail: "새 버전이 나오면 묻지 않고 설치합니다. 설치하는 1~2분 동안 러너가 잠깐 사라집니다.",
                         isOn: $updater.autoUpdate)
        }
    }

    private var status: String {
        switch updater.state {
        case .unavailable(let reason): return reason
        case .idle: return "6시간마다 확인"
        case .checking: return "확인 중…"
        case .upToDate: return "최신 버전"
        case .available(let count, let latest): return "새 커밋 \(count)개: \(latest)"
        case .updating: return "받아서 빌드하는 중… (끝나면 다시 켜집니다)"
        case .failed(let reason): return reason
        }
    }

    private var statusColor: Color {
        switch updater.state {
        case .available: return .accentColor
        case .failed: return .orange
        default: return .secondary
        }
    }
}

/// 제목 아래 한 줄 설명. 괄호 설명을 이름에 섞지 않고 따로 둔다.
private struct DetailLabel: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) { DetailLabel(title, detail: detail) }
    }
}

/// 설정 창의 고른 탭. `@State`를 못 쓰는 이유는 HoverFlag 참고.
final class SettingsTabState: ObservableObject {
    @Published var selection: SettingsView.Tab

    init(_ selection: SettingsView.Tab) {
        self.selection = selection
    }
}

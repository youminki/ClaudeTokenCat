import AppKit
import SwiftUI
import Combine
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let animator = SpriteAnimator()
    private let engine = UsageEngine()
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var dailyDetailWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: SpriteFrames.spriteSize.width + 4)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        animator.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        animator.appearanceProvider = { [weak self] in
            self?.statusItem.button?.effectiveAppearance
        }
        animator.runnerProvider = { [weak self] in
            self?.engine.settings.runner ?? .cat
        }
        animator.themeProvider = { [weak self] in
            self?.engine.settings.spriteTheme ?? .auto
        }
        animator.set(display: .normal(.sleeping))
        statusItem.button?.setAccessibilityLabel("TokenCat 사용량")

        Publishers.CombineLatest(engine.$sessionGauge, engine.$weeklyGauge)
            .map { Self.tooltip(session: $0, weekly: $1) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.statusItem.button?.toolTip = text }
            .store(in: &cancellables)

        Publishers.CombineLatest4(engine.$sessionGauge, engine.$weeklyGauge, engine.$alertLevel,
                                  engine.settings.$menuBarLabel)
            .map { Self.statusLabel($3, session: $0, weekly: $1, alertLevel: $2) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] label in self?.applyStatusLabel(label) }
            .store(in: &cancellables)

        // 잠자기 동안 공식 값이 유예 시간을 넘겼을 수 있다. 네트워크가 붙을 틈을 두고 다시 읽는다.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.engine.refreshNow(forceOfficial: true) }
            .store(in: &cancellables)

        // 러너·색상 변경 → 프레임 다시 그리기
        engine.settings.$spriteTheme.dropFirst().map { _ in }
            .merge(with: engine.settings.$runner.dropFirst().map { _ in })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.animator.reloadFrames() }
            .store(in: &cancellables)

        // 한도 오버라이드(§F2): 80% 이상 지침, 95% 이상 경고. 속도 상태보다 우선
        Publishers.CombineLatest(engine.$catState, engine.$alertLevel)
            .map { state, level -> SpriteDisplay in
                switch level {
                case .critical: return .alert
                case .tired: return .tired
                case .normal: return .normal(state)
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] display in self?.animator.set(display: display) }
            .store(in: &cancellables)

        Notifier.shared.requestAuthorization()
        engine.start()
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)   // RunCat 스타일 다크 팝오버
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(engine: engine, settings: engine.settings,
                                  openSettings: { [weak self] in self?.openSettings() },
                                  openDailyDetail: { [weak self] in self?.openDailyDetail() }))
        if let button = statusItem.button {
            engine.refreshNow()   // 여는 순간 JSONL 재스캔 + 공식 재조회(30초 스로틀)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        self.popover = popover
    }

    private func openSettings() {
        settingsWindow = showWindow(settingsWindow, title: "TokenCat 설정",
                                    style: [.titled, .closable, .resizable]) {   // 세로 드래그로 크기 조절
            SettingsView(settings: engine.settings, engine: engine)
        }
    }

    private func openDailyDetail() {
        dailyDetailWindow = showWindow(dailyDetailWindow, title: "일별 사용량", style: [.titled, .closable]) {
            DailyDetailView(engine: engine)
        }
    }

    /// 창은 한 번만 만들고 다시 열 때는 앞으로 가져온다.
    private func showWindow<Content: View>(_ existing: NSWindow?, title: String, style: NSWindow.StyleMask,
                                           content: () -> Content) -> NSWindow {
        popover?.performClose(nil)
        let window = existing ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = style
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    private struct StatusLabel: Equatable {
        let text: String
        let level: UsageAlertLevel
    }

    /// 고양이 옆 사용률. 추정값은 "~"를 붙인다.
    /// 색은 표시 중인 %의 단계로 정하되, 엔진이 아직 판단을 보류 중(alertLevel == .normal)이면 칠하지 않는다.
    private static func statusLabel(_ label: MenuBarLabel, session: GaugeReading, weekly: GaugeReading,
                                    alertLevel: UsageAlertLevel) -> StatusLabel? {
        let gauge: GaugeReading
        switch label {
        case .off: return nil
        case .session: gauge = session
        case .weekly: gauge = weekly
        case .higher: gauge = session.percent >= weekly.percent ? session : weekly
        }
        let percent = Int(min(gauge.percent, 999).rounded())
        return StatusLabel(text: "\(gauge.isOfficial ? "" : "~")\(percent)%",
                           level: min(UsageAlertLevel.level(percent: gauge.percent), alertLevel))
    }

    private static let statusLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    private func applyStatusLabel(_ label: StatusLabel?) {
        guard let button = statusItem.button else { return }
        guard let label else {
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = SpriteFrames.spriteSize.width + 4
            return
        }
        button.font = Self.statusLabelFont
        switch label.level {
        case .normal:
            button.title = label.text   // 일반 title이라야 메뉴바 기본 글자색(다크/라이트)을 따른다
        case .tired, .critical:
            button.attributedTitle = NSAttributedString(string: label.text, attributes: [
                .font: Self.statusLabelFont,
                .foregroundColor: label.level == .critical ? NSColor.systemRed : NSColor.systemOrange,
            ])
        }
        button.imagePosition = .imageLeft
        statusItem.length = NSStatusItem.variableLength
    }

    /// 메뉴바 아이콘에 마우스를 올리면 현재 사용률을 보여준다.
    private static func tooltip(session: GaugeReading, weekly: GaugeReading) -> String {
        func line(_ name: String, _ gauge: GaugeReading) -> String {
            "\(name) \(Format.percent(gauge.percent))\(gauge.isOfficial ? "" : " (추정)")"
        }
        return "TokenCat · \(line("세션", session)) · \(line("주간", weekly))"
    }
}

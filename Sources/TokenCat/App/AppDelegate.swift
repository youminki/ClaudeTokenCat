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

        // 러너 색상 변경 → 프레임 다시 그리기
        engine.settings.$spriteTheme
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.animator.reloadFrames() }
            .store(in: &cancellables)

        // 한도 오버라이드(§F2): 80%+ 🥵, 95%+ ⚠️ — 속도 상태보다 우선
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
        dailyDetailWindow = showWindow(dailyDetailWindow, title: "일별 사용 내역", style: [.titled, .closable]) {
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

    /// 메뉴바 아이콘에 마우스를 올리면 현재 사용률을 보여준다.
    private static func tooltip(session: GaugeReading, weekly: GaugeReading) -> String {
        func line(_ name: String, _ gauge: GaugeReading) -> String {
            "\(name) \(Format.percent(gauge.percent))\(gauge.isOfficial ? "" : " (추정)")"
        }
        return "TokenCat · \(line("세션", session)) · \(line("주간", weekly))"
    }
}

import AppKit
import SwiftUI
import Combine
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem!
    private let animator = SpriteAnimator()
    /// 러너 레이어를 담는 뷰. AppKit이 버튼 레이어를 다시 만들어도 러너가 사라지지 않게 따로 둔다.
    private let spriteView = PassthroughLayerView()
    private let engine = UsageEngine()
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var dailyDetailWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    /// 러너 칸 배율. 상태 버튼은 22pt지만 메뉴바 창은 더 높을 수 있어(macOS 27에서 30pt) 창 높이까지 키운다.
    private var menuScale: CGFloat = 1
    /// 설정의 메뉴바 크기. 키운 만큼 칸을 옆으로 넓혀 캐릭터가 잘리지 않게 한다.
    private var menuZoom: CGFloat = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: spriteCanvas.width + 4)
        // 이름이 있어야 사용자가 ⌘로 끌어 옮긴 자리를 macOS가 기억한다. 없으면 켤 때마다 맨 왼쪽에 놓여
        // 메뉴가 긴 앱이 앞에 오면 가장 먼저 «로 접힌다.
        statusItem.autosaveName = "TokenCat"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        if let button = statusItem.button {
            // 버튼 크기·글자 배치는 투명한 자리 표시 이미지로 잡고, 러너는 그 위 레이어에서 재생한다.
            button.image = NSImage(size: NSSize(width: spriteCanvas.width, height: Stage.size.height))
            spriteView.layer = animator.layer
            spriteView.wantsLayer = true
            button.addSubview(spriteView)
            // 버튼(22pt)이 자식 뷰를 자르면 메뉴바 창 높이까지 키운 러너의 위아래가 잘린다
            if #available(macOS 14, *) { button.clipsToBounds = false }
            layoutSprite()
        }
        animator.appearanceProvider = { [weak self] in
            self?.statusItem.button?.effectiveAppearance
        }
        animator.characterProvider = { [weak self] in
            self?.engine.settings.character ?? Runner.cat.character
        }
        animator.themeProvider = { [weak self] in
            self?.engine.settings.spriteTheme ?? .auto
        }
        animator.smoothnessProvider = { [weak self] in
            self?.engine.settings.smoothness ?? .smooth
        }
        animator.tricksEnabledProvider = { [weak self] in
            self?.engine.settings.tricksEnabled ?? true
        }
        animator.zoomProvider = { [weak self] in
            self?.engine.settings.runnerSize.zoom ?? 1
        }
        animator.set(display: .normal(.sleeping))
        // 메뉴바가 있는 화면이 바뀌면(레티나↔일반, 메뉴바 높이) 레이어 배율과 칸 크기를 맞춘다
        NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
                   NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification,
                                                        object: statusItem.button?.window))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layoutSprite() }
            .store(in: &cancellables)
        statusItem.button?.setAccessibilityLabel("TokenCat 사용량")

        Publishers.CombineLatest(engine.$sessionGauge, engine.$weeklyGauge)
            .map { Self.tooltip(session: $0, weekly: $1) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in self?.statusItem.button?.toolTip = text }
            .store(in: &cancellables)

        Publishers.CombineLatest3(engine.$sessionGauge, engine.$weeklyGauge, engine.settings.$menuBarLabel)
            .map { Self.statusLabel($2, session: $0, weekly: $1) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] label in self?.applyStatusLabel(label) }
            .store(in: &cancellables)

        // 잠자기 동안 공식 값이 유예 시간을 넘겼을 수 있다. 네트워크가 붙을 틈을 두고 다시 읽는다.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.engine.refreshNow(forceOfficial: true) }
            .store(in: &cancellables)

        // 러너·색상·부드러움 변경 → 프레임 다시 그리기 (@Published는 값이 바뀌기 전에 알리므로 한 박자 뒤에)
        engine.settings.$spriteTheme.dropFirst().map { _ in }
            .merge(with: engine.settings.$runner.dropFirst().map { _ in },
                   engine.settings.$smoothness.dropFirst().map { _ in },
                   engine.settings.$customRunnerID.dropFirst().map { _ in },
                   engine.settings.$runnerSize.dropFirst().map { _ in },
                   CustomRunnerStore.shared.$runners.dropFirst().map { _ in },
                   PetdexStore.shared.$pets.dropFirst().map { _ in })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.animator.reloadFrames() }
            .store(in: &cancellables)
        engine.settings.$runnerSize.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layoutSprite() }
            .store(in: &cancellables)

        // 한도 오버라이드(§F2): 80% 이상 지침, 95% 이상 경고. 속도 상태보다 우선
        Publishers.CombineLatest(engine.$catState, engine.$alertLevel)
            .map { SpriteDisplay(state: $0, level: $1) }
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
        popover.delegate = self
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)   // RunCat 스타일 다크 팝오버
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(engine: engine, settings: engine.settings,
                                  openSettings: { [weak self] in self?.openSettings() },
                                  openDailyDetail: { [weak self] in self?.openDailyDetail() },
                                  performTrick: { [weak self] trick in self?.animator.perform(trick) }))
        if let button = statusItem.button {
            engine.refreshNow()   // 여는 순간 JSONL 재스캔 + 공식 재조회(30초 스로틀)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        self.popover = popover
    }

    /// 닫힌 팝오버의 화면을 놓아 준다. 무대 애니메이션이 보이지 않는 채로 돌지 않게.
    func popoverDidClose(_ notification: Notification) {
        // 닫히는 애니메이션 중에 다시 열었으면 새 팝오버는 건드리지 않는다
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        closed.contentViewController = nil
        popover = nil
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

    /// 고양이 옆 사용률. 공식 값이 없으면 "--%". 색은 표시 중인 %의 단계로 정한다.
    private static func statusLabel(_ label: MenuBarLabel, session: GaugeReading?, weekly: GaugeReading?) -> StatusLabel? {
        let gauge: GaugeReading?
        switch label {
        case .off: return nil
        case .session: gauge = session
        case .weekly: gauge = weekly
        case .higher: gauge = [session, weekly].compactMap { $0 }.max { $0.percent < $1.percent }
        }
        guard let gauge else { return StatusLabel(text: "--%", level: .normal) }
        return StatusLabel(text: "\(gauge.displayPercent)%", level: UsageAlertLevel.level(percent: gauge.percent))
    }

    private static let statusLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    private func applyStatusLabel(_ label: StatusLabel?) {
        guard let button = statusItem.button else { return }
        guard let label else {
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = spriteCanvas.width + 4
            DispatchQueue.main.async { self.layoutSprite() }   // 길이가 줄어든 뒤 배치가 끝나면
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
        DispatchQueue.main.async { self.layoutSprite() }   // 길이가 바뀐 뒤 버튼 배치가 끝나면
    }

    private var spriteCanvas: NSSize {
        NSSize(width: Stage.size.width * menuZoom * menuScale, height: Stage.size.height * menuScale)
    }

    /// 자리 표시 이미지가 놓인 자리에 러너 레이어를 맞춘다. 레이어는 버튼 위아래로 넘쳐 메뉴바 창 높이를 채운다.
    private func layoutSprite() {
        guard let button = statusItem.button, let cell = button.cell else { return }
        let barHeight = button.window?.frame.height ?? NSStatusBar.system.thickness
        // 노치 화면처럼 메뉴바가 아주 높아도 항목이 너무 넓어져 노치 뒤로 숨지 않게 상한을 둔다
        let scale = min(max(1, barHeight / Stage.size.height), 1.6)
        let zoom = engine.settings.runnerSize.zoom
        if scale != menuScale || zoom != menuZoom {
            menuScale = scale
            menuZoom = zoom
            button.image = NSImage(size: NSSize(width: spriteCanvas.width, height: Stage.size.height))
            if button.title.isEmpty && button.attributedTitle.length == 0 { statusItem.length = spriteCanvas.width + 4 }
            DispatchQueue.main.async { self.layoutSprite() }   // 길이가 바뀐 뒤 버튼 배치가 끝나면
            return
        }
        button.layoutSubtreeIfNeeded()
        let imageRect = cell.imageRect(forBounds: button.bounds)
        let backing = button.window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteView.frame = NSRect(x: imageRect.minX, y: (button.bounds.height - spriteCanvas.height) / 2,
                                  width: spriteCanvas.width, height: spriteCanvas.height)
        animator.layer.frame = spriteView.bounds
        animator.layer.contentsScale = backing
        CATransaction.commit()
        animator.pixelScale = (backing * menuScale * 4).rounded() / 4
    }

    /// 메뉴바 아이콘에 마우스를 올리면 현재 사용률을 보여준다.
    private static func tooltip(session: GaugeReading?, weekly: GaugeReading?) -> String {
        func line(_ name: String, _ gauge: GaugeReading?) -> String {
            "\(name) \(gauge.map { "\($0.displayPercent)" } ?? "--")%"
        }
        return "TokenCat · \(line("세션", session)) · \(line("주간", weekly))"
    }
}

/// 클릭은 아래 상태바 버튼으로 넘기는 레이어 전용 뷰.
final class PassthroughLayerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

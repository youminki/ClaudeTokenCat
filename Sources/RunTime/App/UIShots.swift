import AppKit
import SwiftUI

/// 화면 점검: 팝오버·설정·일별·순위표를 실제 데이터로 창에 띄워 PNG로 저장한다.
/// `ImageRenderer`는 Form·Toggle 같은 AppKit 컨트롤을 그리지 못해서 창에 올린 뒤 그 뷰를 찍는다.
@MainActor
enum UIShots {
    static func run(to directory: URL, engine: UsageEngine) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("failed: \(error)")
            exit(1)
        }
        // 찍힌 그림에는 창 배경이 빠지므로 뷰 뒤에 배경을 직접 깐다. 팝오버는 실제 팝오버 바탕과 비슷한 색.
        let popoverBackground = Color(white: 0.16)
        let windowBackground = Color(nsColor: .windowBackgroundColor)
        let screens: [(name: String, appearance: NSAppearance.Name, height: CGFloat?, view: AnyView)] = [
            ("popover", .darkAqua, nil, AnyView(PopoverView(engine: engine, settings: engine.settings).background(popoverBackground))),
            ("settings-general", .darkAqua, 720, AnyView(SettingsView(settings: engine.settings, engine: engine).background(windowBackground))),
            ("settings-general-light", .aqua, 720, AnyView(SettingsView(settings: engine.settings, engine: engine).background(windowBackground))),
            ("settings-runner", .darkAqua, 720,
             AnyView(SettingsView(settings: engine.settings, engine: engine, initialTab: .runner).background(windowBackground))),
            ("settings-usage", .darkAqua, 720,
             AnyView(SettingsView(settings: engine.settings, engine: engine, initialTab: .usage).background(windowBackground))),
            ("daily", .darkAqua, nil, AnyView(DailyDetailView(engine: engine).background(windowBackground))),
            ("leaderboard", .darkAqua, nil, AnyView(LeaderboardView().background(windowBackground))),
        ]
        let windows = screens.map { screen -> NSWindow in
            let window = NSWindow(contentViewController: NSHostingController(rootView: screen.view))
            window.styleMask = [.titled]
            window.appearance = NSAppearance(named: screen.appearance)
            // 설정처럼 스크롤되는 창은 최대 높이로 펼쳐 한 장에 담는다
            if let height = screen.height { window.setContentSize(NSSize(width: window.frame.width, height: height)) }
            // 화면 밖에 두어 사용자 작업을 가리지 않는다
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderBack(nil)
            return window
        }
        // 무대 애니메이션과 비동기로 오는 순위·사용량이 자리 잡을 때까지 기다린다
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            for (screen, window) in zip(screens, windows) {
                guard let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = directory.appendingPathComponent("\(screen.name).png")
                do {
                    try rep.representation(using: .png, properties: [:])?.write(to: url)
                    print("saved: \(url.path) \(Int(view.bounds.width))×\(Int(view.bounds.height))")
                } catch {
                    print("failed: \(url.path) \(error)")
                    exit(1)
                }
            }
            exit(0)
        }
    }
}

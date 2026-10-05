import AppKit
import UsageCore

/// 메뉴바에 표시할 스프라이트 종류: 5단계 상태 + 한도 임박 오버라이드 (§F2).
enum SpriteDisplay: Equatable {
    case normal(CatState)
    case tired    // 사용률 80%+, 상태와 무관하게 오버라이드
    case alert    // 사용률 95%+, 빨간 경고

    var frameInterval: TimeInterval {
        switch self {
        case .normal(let state): return state.frameInterval
        case .tired: return 0.400
        case .alert: return 0.500
        }
    }

    /// 프레임 캐시 키.
    var key: String {
        switch self {
        case .normal(let state): return state.rawValue
        case .tired: return "tired"
        case .alert: return "alert"
        }
    }
}

/// 러너 색상. 코드로 그린 러너에만 적용되고, 커스텀 PNG 에셋은 원본 색 그대로.
enum SpriteTheme: String, CaseIterable {
    case auto      // labelColor — 다크/라이트 메뉴바 자동
    case orange
    case sky
    case pink
    case green

    var displayName: String {
        switch self {
        case .auto: return "자동"
        case .orange: return "주황"
        case .sky: return "하늘"
        case .pink: return "분홍"
        case .green: return "초록"
        }
    }

    var bodyColor: NSColor {
        switch self {
        case .auto: return .labelColor
        case .orange: return .systemOrange
        case .sky: return .systemTeal
        case .pink: return .systemPink
        case .green: return .systemGreen
        }
    }
}

/// 상태별 스프라이트 프레임 로더.
///
/// 에셋 교체: `Sources/TokenCat/Assets/`에 `<러너>_<상태>_<번호>.png`를 넣고 다시 빌드하면
/// 코드로 그린 러너 대신 자동 사용된다 (Assets/README.md 참조). 예: cat_run_0.png ... cat_run_7.png
enum SpriteFrames {

    static let spriteSize = NSSize(width: 36, height: 22)

    static func frames(for display: SpriteDisplay, runner: Runner, theme: SpriteTheme) -> [NSImage] {
        let body = theme.bodyColor
        let art = runner.art
        let prefix = runner.rawValue
        let key = "\(prefix)|\(theme.rawValue)"
        switch display {
        case .normal(.sleeping):
            return loadAssets(named: "\(prefix)_sleep", count: 2) ?? generated("sleep|\(key)") {
                (0..<2).map { PixelRunner.sleepFrame(art, index: $0, body: body) }
            }
        case .normal(.rainbow):
            // 무지개 전용 에셋 → 달리기 에셋 고속 재생 → 생성 프레임(트레일 포함) 순
            return loadAssets(named: "\(prefix)_rainbow", count: 8)
                ?? loadAssets(named: "\(prefix)_run", count: 8)
                ?? generated("rainbow|\(key)") {
                    (0..<8).map { PixelRunner.runFrame(art, index: $0, rainbowTrail: true, body: body) }
                }
        case .normal(.walking), .normal(.running), .normal(.dashing):
            return loadAssets(named: "\(prefix)_run", count: 8) ?? generated("run|\(key)") {
                (0..<8).map { PixelRunner.runFrame(art, index: $0, rainbowTrail: false, body: body) }
            }
        case .tired:
            return loadAssets(named: "\(prefix)_tired", count: 2) ?? generated("tired|\(key)") {
                (0..<2).map { PixelRunner.tiredFrame(art, index: $0, body: body) }
            }
        case .alert:
            // 경고는 테마와 무관하게 항상 빨강
            return loadAssets(named: "\(prefix)_alert", count: 2) ?? generated("alert|\(prefix)") {
                (0..<2).map { PixelRunner.alertFrame(art, index: $0) }
            }
        }
    }

    /// 설정 화면 미리보기용 한 장 (달리기 첫 포즈).
    static func preview(runner: Runner, theme: SpriteTheme) -> NSImage {
        frames(for: .normal(.running), runner: runner, theme: theme)[0]
    }

    // MARK: - 파일 에셋

    private static func loadAssets(named prefix: String, count: Int) -> [NSImage]? {
        guard let assetsDir = Bundle.module.resourceURL?.appendingPathComponent("Assets") else { return nil }
        var frames: [NSImage] = []
        for i in 0..<count {
            let url = assetsDir.appendingPathComponent("\(prefix)_\(i).png")
            guard let image = NSImage(contentsOf: url) else { return nil } // 하나라도 없으면 전체 폴백
            image.size = spriteSize
            frames.append(image)
        }
        return frames
    }

    // MARK: - 코드 생성 프레임 캐시

    private static var generatedCache: [String: [NSImage]] = [:]

    private static func generated(_ key: String, _ make: () -> [NSImage]) -> [NSImage] {
        if let cached = generatedCache[key] { return cached }
        let frames = make()
        generatedCache[key] = frames
        return frames
    }
}

/// RunnerArt 픽셀맵(1칸 = 2pt)을 그린다. 상태 표현(무지개 트레일, Zzz, 땀방울, 느낌표)은 러너와 무관하게 여기서 얹는다.
/// labelColor로 그려서 다크/라이트 메뉴바에 자동 대응. 래스터라이즈 시점의 appearance가 적용된다 (SpriteRasterizer 참조).
enum PixelRunner {

    private static let cell: CGFloat = 2
    private static let columns = 18
    private static let rows = 11

    /// 달리기 프레임. 4포즈 × 2회전 = 8프레임.
    static func runFrame(_ art: RunnerArt, index: Int, rainbowTrail: Bool, body: NSColor) -> NSImage {
        let pose = index % 4
        return draw { fill in
            if rainbowTrail {
                // 무지개 트레일 (몸 뒤 왼쪽): 6색 가로 줄무늬, 프레임마다 1픽셀 흔들림
                let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow,
                                         .systemGreen, .systemBlue, .systemPurple]
                let wave = index % 2
                for (i, color) in colors.enumerated() {
                    fill(0, 2 + i + wave, 4 - wave, 1, color)
                }
            }
            paint(art.body + art.legs[pose], dy: art.bob[pose], body: body, fill: fill)
        }
    }

    /// 잠자기: 러너의 잠든 자세 + 떠오르는 Z.
    static func sleepFrame(_ art: RunnerArt, index: Int, body: NSColor) -> NSImage {
        draw { fill in
            paint(art.sleep, dy: 0, body: body, fill: fill)
            // Z 3×3 픽셀 글자, 프레임마다 위치 이동
            let (x, y) = index == 0 ? (15, 1) : (14, 0)
            fill(x, y, 3, 1, body)
            fill(x + 1, y + 1, 1, 1, body)
            fill(x, y + 2, 3, 1, body)
        }
    }

    /// 지침 (사용률 80%+): 앉은 자세로 들썩이며 땀방울이 떨어진다.
    static func tiredFrame(_ art: RunnerArt, index: Int, body: NSColor) -> NSImage {
        let pant = index % 2
        return draw { fill in
            paint(art.sit, dy: pant, body: body, fill: fill)
            fill(17, 1 + pant * 2, 1, 1, .systemBlue)
        }
    }

    /// 경고 (사용률 95%+): 선 자세 전체를 빨강으로 + 깜빡이는 느낌표.
    static func alertFrame(_ art: RunnerArt, index: Int) -> NSImage {
        let red = NSColor.systemRed
        return draw { fill in
            paint(art.body + art.legs[3], dy: art.bob[3], body: red, accent: red, fill: fill)
            if index == 0 {
                fill(0, 1, 1, 4, red)
                fill(0, 6, 1, 1, red)
            }
        }
    }

    private typealias Fill = (_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor) -> Void

    /// 픽셀맵을 dy만큼 내려 그린다. 그리드 밖은 버린다.
    private static func paint(_ map: [String], dy: Int, body: NSColor, accent: NSColor = .systemOrange,
                              fill: Fill) {
        for (row, line) in map.enumerated() where (0..<rows).contains(row + dy) {
            for (column, pixel) in line.enumerated() where column < columns {
                switch pixel {
                case "#": fill(column, row + dy, 1, 1, body)
                case "o": fill(column, row + dy, 1, 1, accent)
                default: break
                }
            }
        }
    }

    /// 그리드 좌표(원점 좌상단)로 그리는 이미지.
    private static func draw(_ content: @escaping (Fill) -> Void) -> NSImage {
        NSImage(size: SpriteFrames.spriteSize, flipped: true) { _ in
            content { x, y, w, h, color in
                color.setFill()
                NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                       width: CGFloat(w) * cell, height: CGFloat(h) * cell).fill()
            }
            return true
        }
    }
}

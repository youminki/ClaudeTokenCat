import AppKit
import UsageCore

/// 메뉴바에 표시할 스프라이트 종류: 5단계 상태 + 한도 임박 오버라이드 (§F2).
enum SpriteDisplay: Equatable {
    case normal(CatState)
    case tired    // 🥵 사용률 80%+ — 상태와 무관하게 오버라이드
    case alert    // ⚠️ 사용률 95%+ — 빨간 경고

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

/// 러너 색상 테마 (§F3 🐾 — 고양이 1종 + 색상 3종).
/// 코드 생성 플레이스홀더에만 적용, 커스텀 PNG 에셋은 원본 색 그대로.
enum SpriteTheme: String, CaseIterable {
    case auto      // labelColor — 다크/라이트 메뉴바 자동
    case orange
    case sky

    var displayName: String {
        switch self {
        case .auto: return "자동"
        case .orange: return "주황"
        case .sky: return "하늘"
        }
    }

    var bodyColor: NSColor {
        switch self {
        case .auto: return .labelColor
        case .orange: return .systemOrange
        case .sky: return .systemTeal
        }
    }

    var next: SpriteTheme {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 상태별 스프라이트 프레임 로더.
///
/// 에셋 교체: `Sources/TokenCat/Assets/`에 아래 이름의 PNG를 넣고 다시 빌드하면
/// 코드 생성 플레이스홀더 대신 자동 사용된다 (Assets/README.md 참조).
///   cat_run_0.png ... cat_run_7.png       (달리기 8프레임, 36×22pt @1x / 72×44 @2x)
///   cat_rainbow_0.png ... cat_rainbow_7.png (무지개 모드 전용 8프레임 — 없으면 cat_run 재사용)
///   cat_sleep_0.png, cat_sleep_1.png      (잠자기 2프레임)
///   cat_tired_0.png, cat_tired_1.png      (지침 2프레임, 사용률 80%+)
///   cat_alert_0.png, cat_alert_1.png      (경고 2프레임, 사용률 95%+)
enum SpriteFrames {

    static let spriteSize = NSSize(width: 36, height: 22)

    static func frames(for display: SpriteDisplay, theme: SpriteTheme) -> [NSImage] {
        let body = theme.bodyColor
        switch display {
        case .normal(.sleeping):
            return loadAssets(named: "cat_sleep", count: 2) ?? generated("sleep|\(theme.rawValue)") {
                (0..<2).map { PixelCat.sleepFrame(index: $0, body: body) }
            }
        case .normal(.rainbow):
            // 무지개 전용 에셋 → 달리기 에셋 고속 재생 → 생성 프레임(트레일 포함) 순
            return loadAssets(named: "cat_rainbow", count: 8)
                ?? loadAssets(named: "cat_run", count: 8)
                ?? generated("rainbow|\(theme.rawValue)") {
                    (0..<8).map { PixelCat.runFrame(index: $0, rainbowTrail: true, body: body) }
                }
        case .normal(.walking), .normal(.running), .normal(.dashing):
            return loadAssets(named: "cat_run", count: 8) ?? generated("run|\(theme.rawValue)") {
                (0..<8).map { PixelCat.runFrame(index: $0, rainbowTrail: false, body: body) }
            }
        case .tired:
            return loadAssets(named: "cat_tired", count: 2) ?? generated("tired|\(theme.rawValue)") {
                (0..<2).map { PixelCat.tiredFrame(index: $0, body: body) }
            }
        case .alert:
            // 경고는 테마와 무관하게 항상 빨강
            return loadAssets(named: "cat_alert", count: 2) ?? generated("alert") {
                (0..<2).map { PixelCat.alertFrame(index: $0) }
            }
        }
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

    // MARK: - 코드 생성 플레이스홀더 캐시

    private static var generatedCache: [String: [NSImage]] = [:]

    private static func generated(_ key: String, _ make: () -> [NSImage]) -> [NSImage] {
        if let cached = generatedCache[key] { return cached }
        let frames = make()
        generatedCache[key] = frames
        return frames
    }
}

/// 18×11 그리드(1칸 = 2pt) 픽셀 고양이를 코드로 그린다.
/// labelColor로 그려서 다크/라이트 메뉴바에 자동 대응
/// (래스터라이즈 시점의 appearance가 적용됨 — SpriteRasterizer 참조).
enum PixelCat {

    private static let cell: CGFloat = 2

    /// 달리기 프레임. 4포즈 × 2회전 = 8프레임, 다리 위치와 몸통 높이 변화.
    static func runFrame(index: Int, rainbowTrail: Bool, body: NSColor = .labelColor) -> NSImage {
        let pose = index % 4
        return draw(body: body) { fill, fillColor in
            // 몸통 바운스: 다리가 모이는 포즈에서 1픽셀 내려앉음
            let bob = (pose == 2) ? 1 : 0

            if rainbowTrail {
                // 무지개 트레일 (꼬리 뒤 왼쪽): 6색 가로 줄무늬, 프레임마다 1픽셀 흔들림
                let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow,
                                         .systemGreen, .systemBlue, .systemPurple]
                let wave = index % 2
                for (i, color) in colors.enumerated() {
                    fillColor(0, 2 + i + wave % 2, 4 - wave, 1, color)
                }
            }

            // 꼬리 (왼쪽 위로 들림)
            fill(3, 2 + bob, 2, 1)
            fill(4, 3 + bob, 1, 1)
            // 몸통
            fill(5, 4 + bob, 9, 4)
            // 머리 (오른쪽, 진행 방향)
            fill(12, 2 + bob, 5, 4)
            // 귀
            fill(12, 1 + bob, 1, 1)
            fill(16, 1 + bob, 1, 1)

            // 다리: 앞다리 x=12, 뒷다리 x=6 기준, 포즈별 벌림
            switch pose {
            case 0: // 쭉 뻗음
                fill(4, 8 + bob, 2, 2)   // 뒷다리 뒤로
                fill(14, 8 + bob, 2, 2)  // 앞다리 앞으로
            case 1: // 모아드는 중
                fill(5, 8 + bob, 2, 2)
                fill(13, 8 + bob, 2, 2)
            case 2: // 웅크림 (착지)
                fill(7, 8 + bob, 2, 2)
                fill(11, 8 + bob, 2, 2)
            default: // 다시 뻗는 중
                fill(6, 8 + bob, 2, 2)
                fill(12, 8 + bob, 2, 2)
            }
        }
    }

    /// 잠자기 프레임: 웅크린 몸 + 깜빡이는 Zzz.
    static func sleepFrame(index: Int, body: NSColor = .labelColor) -> NSImage {
        draw(body: body) { fill, _ in
            // 웅크린 몸통 (타원형 덩어리)
            fill(5, 6, 9, 4)
            fill(6, 5, 7, 1)
            // 머리 (몸에 파묻힘)
            fill(11, 4, 4, 3)
            fill(11, 3, 1, 1)
            fill(14, 3, 1, 1)
            // 꼬리 (몸을 감쌈)
            fill(4, 8, 2, 2)
            // Z — 3×3 픽셀 글자(윗줄·대각·아랫줄), 프레임마다 떠오르듯 위치 이동
            func zGlyph(_ x: Int, _ y: Int) {
                fill(x, y, 3, 1)
                fill(x + 1, y + 1, 1, 1)
                fill(x, y + 2, 3, 1)
            }
            if index == 0 {
                zGlyph(15, 1)
            } else {
                zGlyph(14, 0)
            }
        }
    }

    /// 🥵 지친 프레임 (사용률 80%+): 주저앉아 헐떡임 + 땀방울.
    static func tiredFrame(index: Int, body: NSColor = .labelColor) -> NSImage {
        let pant = index % 2   // 헐떡임: 몸통 1픽셀 들썩
        return draw(body: body) { fill, fillColor in
            // 주저앉은 몸통
            fill(4, 6 - pant, 9, 4 + pant)
            // 고개 든 머리 (오른쪽)
            fill(11, 2, 5, 4)
            fill(11, 1, 1, 1)
            fill(15, 1, 1, 1)
            // 벌린 입 (머리 아래 틈)
            if pant == 1 { fillColor(14, 5, 2, 1, .clear) }
            // 늘어진 꼬리
            fill(2, 8, 2, 1)
            fill(3, 7, 1, 1)
            // 앞다리만 지탱
            fill(12, 9, 2, 1)
            // 💧 땀방울 (파랑, 프레임마다 낙하)
            fillColor(17, 1 + pant * 2, 1, 1, .systemBlue)
        }
    }

    /// ⚠️ 경고 프레임 (사용률 95%+): 빨간 고양이 + 깜빡이는 느낌표.
    static func alertFrame(index: Int) -> NSImage {
        draw(body: .labelColor) { _, fillColor in
            let red = NSColor.systemRed
            // 서 있는 고양이 전신을 빨강으로
            fillColor(3, 3, 2, 1, red)          // 꼬리
            fillColor(4, 4, 1, 1, red)
            fillColor(5, 4, 9, 4, red)          // 몸통
            fillColor(12, 2, 5, 4, red)         // 머리
            fillColor(12, 1, 1, 1, red)         // 귀
            fillColor(16, 1, 1, 1, red)
            fillColor(6, 8, 2, 2, red)          // 다리 (정지)
            fillColor(12, 8, 2, 2, red)
            // ❗ 느낌표 (홀수 프레임에만 → 깜빡임)
            if index == 0 {
                fillColor(0, 1, 1, 4, red)
                fillColor(0, 6, 1, 1, red)
            }
        }
    }

    /// (x, y, w, h) 그리드 좌표(원점 좌상단)를 받아 그리는 헬퍼. `fill`은 테마 몸통색 사용.
    private static func draw(
        body bodyColor: NSColor,
        _ content: @escaping (_ fill: (Int, Int, Int, Int) -> Void,
                              _ fillColor: (Int, Int, Int, Int, NSColor) -> Void) -> Void
    ) -> NSImage {
        let size = SpriteFrames.spriteSize
        let image = NSImage(size: size, flipped: true) { _ in
            func fillColor(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor) {
                if color == .clear {
                    NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                           width: CGFloat(w) * cell, height: CGFloat(h) * cell)
                        .fill(using: .clear)
                    return
                }
                color.setFill()
                NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                       width: CGFloat(w) * cell, height: CGFloat(h) * cell).fill()
            }
            func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
                fillColor(x, y, w, h, bodyColor)
            }
            content(fill, fillColor)
            return true
        }
        return image
    }
}

import SwiftUI
import UsageCore

/// 팝오버 맨 위 무대. 러너가 시간대별 하늘 아래를 달리고, 속도에 맞춰 배경이 겹겹이 흘러간다.
/// 메뉴바와 달리 프레임을 미리 굽지 않고 화면 주사율대로 매번 계산해 그린다 (팝오버가 열려 있을 때만).
struct RunnerStage: View {
    let display: SpriteDisplay
    let character: RunnerCharacter
    let theme: SpriteTheme
    var onPet: (Trick) -> Void = { _ in }

    @StateObject private var model = StageModel()

    static let height: CGFloat = 150

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: model.reduceMotion)) { timeline in
            Canvas { context, size in
                context.withCGContext { cg in
                    model.draw(cg, size: size, date: timeline.date, display: display, character: character,
                               theme: character.theme(theme))
                }
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
        .overlay { bubbleLayer }
        .contentShape(Rectangle())
        .onTapGesture { onPet(model.pet(character: character, display: display)) }
        .onHover { model.setPointer($0) }
        .onAppear { model.greet(display: display) }
        .onDisappear { model.setPointer(false) }   // 커서를 올린 채 팝오버가 닫혀도 짝을 맞춘다
        .help("러너를 누르면 장난을 쳐요")
        .accessibilityElement()
        .accessibilityLabel(character.name)
        .accessibilityAddTraits(.isButton)
    }

    private var bubbleLayer: some View {
        GeometryReader { geo in
            if let text = model.bubble {
                SpeechBubble(text: text)
                    .position(x: min(geo.size.width * StageModel.runnerAnchor + 74, geo.size.width - 64), y: 24)
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.bubble)
        .allowsHitTesting(false)
    }
}

/// 말풍선. 그림자 없이 얇은 테두리만.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: NSColor(hex: 0x1F1C26)))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.97)))
            .overlay(alignment: .bottomLeading) {
                Triangle().fill(Color(white: 0.97)).frame(width: 7, height: 5).offset(x: 9, y: 4.5)
            }
            .fixedSize()
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}

// MARK: - 무대 상태와 그리기

final class StageModel: ObservableObject {
    @Published var bubble: String?
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// 러너가 서는 가로 위치 (무대 폭 대비).
    static let runnerAnchor: CGFloat = 0.34

    // 아래는 그리는 동안에만 바뀌는 시계 상태. 화면 갱신을 일으키지 않도록 @Published가 아니다.
    private var lastDate: Date?
    private var scroll: CGFloat = 0
    private var speed: CGFloat = 0
    private var gait: CGFloat = 0
    private var trick: (kind: Trick, start: Date)?
    private var lastDisplay: SpriteDisplay?
    private var nextIdle = Date().addingTimeInterval(5)
    private var lastIdleTrick: Trick?
    private var bubbleToken = 0

    private var pointerPushed = false

    func setPointer(_ inside: Bool) {
        guard inside != pointerPushed else { return }
        inside ? NSCursor.pointingHand.push() : NSCursor.pop()
        pointerPushed = inside
    }

    // MARK: 말풍선·장난

    func greet(display: SpriteDisplay) {
        let hour = Calendar.current.component(.hour, from: Date())
        let line: String
        switch display {
        case .tired, .alert, .normal(.sleeping): line = Self.phrases(for: display).randomElement() ?? ""
        default:
            switch hour {
            case 5..<11: line = "좋은 아침"
            case 11..<14: line = "점심은 먹었어?"
            case 14..<18: line = "오후도 힘내"
            case 18..<22: line = "저녁 코딩 중?"
            default: line = "늦었어, 쉬엄쉬엄"
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.say(line, seconds: 2.4) }
    }

    /// 누르면 장난 하나 + 말풍선. 메뉴바 러너도 같은 장난을 하도록 고른 동작을 돌려준다.
    func pet(character: RunnerCharacter, display: SpriteDisplay) -> Trick {
        let kind: Trick
        switch display {
        case .normal(.sleeping): kind = .wakeUp
        case .tired, .alert: kind = .shake
        default: kind = Trick.petting.filter { $0 != trick?.kind }.randomElement() ?? .hop
        }
        trick = (kind, Date())
        nextIdle = Date().addingTimeInterval(kind.duration + 9)
        let line = Bool.random() ? "\(character.sound)!" : (Self.phrases(for: display).randomElement() ?? character.sound)
        say(line, seconds: 1.8)
        return kind
    }

    func say(_ text: String, seconds: Double) {
        bubbleToken += 1
        let token = bubbleToken
        bubble = text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.bubbleToken == token else { return }
            self.bubble = nil
        }
    }

    static func phrases(for display: SpriteDisplay) -> [String] {
        switch display {
        case .normal(.sleeping): return ["쿨쿨...", "5분만 더...", "꿈에서 토큰 세는 중", "음냐음냐"]
        case .normal(.walking): return ["산책 중", "느긋하게 가자", "오늘도 코딩?", "천천히, 꾸준히"]
        case .normal(.running): return ["달린다!", "토큰 냠냠", "좋은 페이스", "가보자고"]
        case .normal(.dashing): return ["질주 중!", "바람을 가른다", "속도 올라간다", "따라올 테면 와 봐"]
        case .normal(.rainbow): return ["무지개 모드!", "전력 질주!", "아무도 못 말려", "토큰이 불탄다"]
        case .tired: return ["헥헥...", "좀 쉬자...", "한도가 가까워", "물 한 잔만..."]
        case .alert: return ["한도 코앞!", "브레이크!", "/usage 확인해", "곧 멈춰야 해"]
        }
    }

    // MARK: 한 프레임

    func draw(_ cg: CGContext, size: CGSize, date: Date, display: SpriteDisplay, character: RunnerCharacter,
              theme: SpriteTheme) {
        let dt = CGFloat(min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1))
        lastDate = date
        let time = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))

        updateTricks(date: date, display: display)
        let active = trick.map { (kind: $0.kind, t: CGFloat(date.timeIntervalSince($0.start) / $0.kind.duration)) }
        if let active, active.t >= 1 { trick = nil }
        let playing = active.flatMap { $0.t < 1 ? $0 : nil }

        // 속도는 목표를 향해 부드럽게 따라간다 (장난 중에는 멈춘다)
        let target: CGFloat = (playing != nil && playing?.kind != .zoom) ? 0 : Self.worldSpeed(display)
        speed += (target - speed) * min(1, dt * 2.4)
        scroll += speed * dt
        if playing == nil { gait += dt / CGFloat(display.cycle) }

        let groundY = size.height - 15
        let scale: CGFloat = 5.0
        let runnerX = size.width * Self.runnerAnchor + speed / 140 * 16
        let origin = CGPoint(runnerX - Stage.size.width / 2 * scale, groundY - Stage.ground * scale)
        let isSpace = display == .normal(.rainbow)
        let sky = Sky.at(hour: Calendar.current.component(.hour, from: date), space: isSpace)

        drawBackdrop(cg, size: size, sky: sky, time: time, groundY: groundY)

        // 러너 장면
        let rig = character.rig
        let frame = playing.map { $0.kind.frame(at: $0.t) } ?? display.motion(at: gait)
        let scene = CharacterScene(rig: rig, pose: frame.pose, transform: frame.transform)
        let bounds = scene.placedBounds

        // 그림자: 높이 뜰수록 옅고 작아진다
        let lift = max(0, Stage.ground - bounds.maxY)
        let shadowW = bounds.width * scale * 0.5 * (1 - min(lift / 14, 0.6))
        cg.setFillColor(NSColor.black.withAlphaComponent(0.28 * (1 - min(lift / 10, 0.8))).cgColor)
        cg.fillEllipse(in: CGRect(x: origin.x + bounds.midX * scale - shadowW / 2, y: groundY - 2.5,
                                  width: shadowW, height: 5))

        if isSpace && playing == nil { drawStarStreaks(cg, size: size, time: time, groundY: groundY) }
        if display == .normal(.dashing) || (isSpace && playing == nil) {
            drawWind(cg, size: size, time: time, groundY: groundY, strong: isSpace)
        }

        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: scale, y: scale)
        let leftEdge = -origin.x / scale
        let loopPhase = gait - floor(gait)
        if playing == nil {
            display.drawLoopEffects(in: cg, scene: scene, phase: loopPhase, tint: .white, front: false, leftEdge: leftEdge)
        }
        var look = CharacterLook(rich: true, palette: theme.richPalette(rig.palette, phase: time / 6),
                                 tint: .white, outline: 0.36)
        look.alarm = display == .alert && playing == nil
        scene.draw(in: cg, look: look)
        if playing == nil {
            display.drawLoopEffects(in: cg, scene: scene, phase: loopPhase, tint: .white, front: true, leftEdge: leftEdge)
        }
        for effect in frame.effects {
            effect.draw(in: cg, around: bounds, tint: .white)
        }
        cg.restoreGState()

        if display == .alert { drawAlarm(cg, size: size, time: time) }
    }

    private func updateTricks(date: Date, display: SpriteDisplay) {
        defer { lastDisplay = display }
        if let previous = lastDisplay, previous != display {
            switch (previous.isAsleep, display) {
            case (true, .normal(let s)) where s != .sleeping: trick = (.wakeUp, date)
            case (false, .normal(.sleeping)): trick = (.fallAsleep, date)
            case (false, .normal(.rainbow)): trick = (.celebrate, date)
            case (_, .tired), (_, .alert): trick = nil
            default: break
            }
        }
        guard trick == nil, date >= nextIdle else { return }
        nextIdle = date.addingTimeInterval(.random(in: 7...14))
        guard display != .tired && display != .alert else { return }
        let pool = (display.isAsleep ? Trick.asleep : Trick.awake).filter { $0 != lastIdleTrick }
        if let kind = pool.randomElement() {
            lastIdleTrick = kind
            trick = (kind, date)
        }
    }

    /// 배경이 흘러가는 속도 (pt/초).
    static func worldSpeed(_ display: SpriteDisplay) -> CGFloat {
        switch display {
        case .normal(.sleeping), .tired, .alert: return 0
        case .normal(.walking): return 16
        case .normal(.running): return 46
        case .normal(.dashing): return 88
        case .normal(.rainbow): return 140
        }
    }

    // MARK: 배경

    private func drawBackdrop(_ cg: CGContext, size: CGSize, sky: Sky, time: CGFloat, groundY: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        if let gradient = CGGradient(colorsSpace: space, colors: [sky.top.cgColor, sky.bottom.cgColor] as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(0, groundY), options: [.drawsAfterEndLocation])
        }

        // 별
        if sky.stars > 0 {
            for i in 0..<34 {
                let x = Self.hash(i, 1) * size.width
                let y = Self.hash(i, 2) * (groundY - 30) + 4
                let twinkle = 0.35 + 0.65 * abs(sin(time * (0.8 + Self.hash(i, 3) * 1.6) + CGFloat(i)))
                let r = 0.5 + Self.hash(i, 4) * 0.9
                cg.setFillColor(NSColor.white.withAlphaComponent(sky.stars * twinkle).cgColor)
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }

        // 해·달
        let orb = CGPoint(size.width * 0.78, sky.orbLow ? groundY - 24 : 26)
        cg.setFillColor(sky.orb.withAlphaComponent(0.16).cgColor)
        cg.fillEllipse(in: CGRect(x: orb.x - 14, y: orb.y - 14, width: 28, height: 28))
        cg.setFillColor(sky.orb.cgColor)
        cg.fillEllipse(in: CGRect(x: orb.x - 8, y: orb.y - 8, width: 16, height: 16))
        if sky.moon {
            cg.setFillColor(sky.top.blended(withFraction: 0.25, of: sky.bottom)?.cgColor ?? sky.top.cgColor)
            cg.fillEllipse(in: CGRect(x: orb.x - 3.5, y: orb.y - 11, width: 16, height: 16))
        }

        // 구름
        if sky.clouds > 0 {
            for i in 0..<4 {
                let span = size.width + 90
                let raw = Self.hash(i, 7) * span - scroll * 0.22 - time * 4
                let x = raw - floor(raw / span) * span - 45
                let y = 30 + Self.hash(i, 8) * 18
                let s = 0.7 + Self.hash(i, 9) * 0.6
                cg.setFillColor(NSColor.white.withAlphaComponent(0.85 * sky.clouds).cgColor)
                for (dx, dy, r) in [(0.0, 0.0, 7.0), (8.0, -3.0, 8.5), (17.0, 0.0, 6.5), (8.0, 2.5, 7.0)] as [(CGFloat, CGFloat, CGFloat)] {
                    cg.fillEllipse(in: CGRect(x: x + dx * s - r * s, y: y + dy * s - r * s, width: r * 2 * s, height: r * 2 * s))
                }
            }
        }

        // 먼 산과 가까운 언덕
        layer(cg, size: size, base: groundY - 20, amplitude: 13, frequency: 0.022, parallax: 0.12, color: sky.far, seed: 1)
        layer(cg, size: size, base: groundY - 7, amplitude: 7, frequency: 0.045, parallax: 0.35, color: sky.near, seed: 2)

        // 땅
        cg.setFillColor(sky.ground.cgColor)
        cg.fill(CGRect(x: 0, y: groundY, width: size.width, height: size.height - groundY))
        cg.setFillColor(sky.edge.withAlphaComponent(0.9).cgColor)
        cg.fill(CGRect(x: 0, y: groundY - 1, width: size.width, height: 2))
        let dash: CGFloat = 26
        let offset = scroll.truncatingRemainder(dividingBy: dash)
        cg.setFillColor(sky.edge.withAlphaComponent(0.35).cgColor)
        var x = -offset
        while x < size.width {
            cg.addPath(CGPath(roundedRect: CGRect(x: x, y: groundY + 5, width: 10, height: 2), cornerWidth: 1,
                              cornerHeight: 1, transform: nil))
            x += dash
        }
        cg.fillPath()
        // 풀 무더기
        let tuftGap: CGFloat = 47
        let tuftOffset = scroll.truncatingRemainder(dividingBy: tuftGap)
        cg.setStrokeColor(sky.edge.withAlphaComponent(0.7).cgColor)
        cg.setLineWidth(1.2)
        cg.setLineCap(.round)
        x = -tuftOffset + 12
        while x < size.width + 10 {
            for dx in [-2.5, 0, 2.5] as [CGFloat] {
                cg.move(to: CGPoint(x + dx * 0.4, groundY - 0.5))
                cg.addLine(to: CGPoint(x + dx, groundY - 4 + abs(dx) * 0.4))
            }
            x += tuftGap
        }
        cg.strokePath()
    }

    /// 사인파를 겹친 능선. 시차를 둬서 멀수록 느리게 흐른다.
    private func layer(_ cg: CGContext, size: CGSize, base: CGFloat, amplitude: CGFloat, frequency: CGFloat,
                       parallax: CGFloat, color: NSColor, seed: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(0, size.height))
        var x: CGFloat = 0
        let shift = scroll * parallax
        while x <= size.width + 4 {
            let w = x + shift
            let y = base - amplitude * (0.55 * sin(w * frequency + seed) + 0.3 * sin(w * frequency * 2.3 + seed * 2)
                                        + 0.15 * sin(w * frequency * 5.1))
            path.addLine(to: CGPoint(x, y))
            x += 4
        }
        path.addLine(to: CGPoint(size.width, size.height))
        path.closeSubpath()
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    /// 무지개 질주 중 뒤로 쏟아지는 별빛.
    private func drawStarStreaks(_ cg: CGContext, size: CGSize, time: CGFloat, groundY: CGFloat) {
        cg.setLineCap(.round)
        for i in 0..<14 {
            let span = size.width + 60
            let raw = Self.hash(i, 11) * span - scroll * (1.2 + Self.hash(i, 12))
            let x = raw - floor(raw / span) * span - 30
            let y = Self.hash(i, 13) * (groundY - 16) + 6
            let length = 10 + Self.hash(i, 14) * 22
            let color = SpriteEffects.rainbow[i % SpriteEffects.rainbow.count].tinted(by: 0.4)
            cg.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(1.2)
            cg.move(to: CGPoint(x, y))
            cg.addLine(to: CGPoint(x + length, y))
            cg.strokePath()
            SpriteEffects.sparkle(cg, at: CGPoint(x, y), radius: 2.2 + sin(time * 6 + CGFloat(i)) * 0.8, color: color)
        }
    }

    private func drawWind(_ cg: CGContext, size: CGSize, time: CGFloat, groundY: CGFloat, strong: Bool) {
        cg.setLineCap(.round)
        for i in 0..<6 {
            let span = size.width + 80
            let raw = Self.hash(i, 21) * span - scroll * 2.2
            let x = raw - floor(raw / span) * span - 40
            let y = 20 + Self.hash(i, 22) * (groundY - 30)
            let length = 24 + Self.hash(i, 23) * 30
            cg.setStrokeColor(NSColor.white.withAlphaComponent(strong ? 0.35 : 0.28).cgColor)
            cg.setLineWidth(1.1)
            cg.move(to: CGPoint(x, y))
            cg.addLine(to: CGPoint(x + length, y))
            cg.strokePath()
        }
    }

    private func drawAlarm(_ cg: CGContext, size: CGSize, time: CGFloat) {
        let pulse = 0.18 + 0.14 * sin(time * 5)
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let center = CGPoint(size.width / 2, size.height / 2)
        if let gradient = CGGradient(colorsSpace: space, colors: [NSColor.systemRed.withAlphaComponent(0).cgColor,
                                                                  NSColor.systemRed.withAlphaComponent(pulse).cgColor] as CFArray,
                                     locations: [0.35, 1]) {
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                  endRadius: size.width * 0.6, options: [.drawsAfterEndLocation])
        }
    }

    /// 0~1 고정 난수 (자리마다 같은 값).
    static func hash(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(CGFloat(i) * 12.9898 + CGFloat(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }
}

/// 시간대별 하늘색.
private struct Sky {
    var top: NSColor
    var bottom: NSColor
    var far: NSColor
    var near: NSColor
    var ground: NSColor
    var edge: NSColor
    var stars: CGFloat = 0
    var clouds: CGFloat = 0
    var orb: NSColor
    var moon = false
    var orbLow = false

    static func at(hour: Int, space: Bool) -> Sky {
        if space {
            return Sky(top: NSColor(hex: 0x120B2E), bottom: NSColor(hex: 0x3A1A6E), far: NSColor(hex: 0x2A1658),
                       near: NSColor(hex: 0x1E1045), ground: NSColor(hex: 0x170C36), edge: NSColor(hex: 0xA17BFF),
                       stars: 1, orb: NSColor(hex: 0xFFE7A3), moon: true)
        }
        switch hour {
        case 5..<8:
            return Sky(top: NSColor(hex: 0x4E5A86), bottom: NSColor(hex: 0xE4B39A), far: NSColor(hex: 0x7F7194),
                       near: NSColor(hex: 0x5B5174), ground: NSColor(hex: 0x3A3352), edge: NSColor(hex: 0xE6C4A8),
                       stars: 0.2, clouds: 0.45, orb: NSColor(hex: 0xF6D6A8), orbLow: true)
        case 8..<17:
            return Sky(top: NSColor(hex: 0x6191C4), bottom: NSColor(hex: 0xBCD6E8), far: NSColor(hex: 0x93B2CC),
                       near: NSColor(hex: 0x739F7C), ground: NSColor(hex: 0x4C7A5C), edge: NSColor(hex: 0xA9CDA2),
                       clouds: 0.9, orb: NSColor(hex: 0xFBF1CF))
        case 17..<20:
            return Sky(top: NSColor(hex: 0x4D4373), bottom: NSColor(hex: 0xE59B80), far: NSColor(hex: 0x7B5B80),
                       near: NSColor(hex: 0x514166), ground: NSColor(hex: 0x372D4D), edge: NSColor(hex: 0xE9B391),
                       clouds: 0.5, orb: NSColor(hex: 0xF4B48A), orbLow: true)
        default:
            return Sky(top: NSColor(hex: 0x131A33), bottom: NSColor(hex: 0x2B3660), far: NSColor(hex: 0x212C52),
                       near: NSColor(hex: 0x19223F), ground: NSColor(hex: 0x131A34), edge: NSColor(hex: 0x4E5E98),
                       stars: 0.85, orb: NSColor(hex: 0xF2EBD0), moon: true)
        }
    }
}

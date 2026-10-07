import AppKit
import GameCore
import SwiftUI

/// 최고 점수와 판 수. 이 Mac에만 저장한다.
enum GameRecords {
    private static let bestKey = "gameBest"
    private static let playsKey = "gamePlays"

    static var best: Int { UserDefaults.standard.integer(forKey: bestKey) }
    static var plays: Int { UserDefaults.standard.integer(forKey: playsKey) }

    static func finish(score: Int) {
        let defaults = UserDefaults.standard
        defaults.set(max(best, score), forKey: bestKey)
        defaults.set(plays + 1, forKey: playsKey)
    }
}

/// 팝오버 무대 위의 한 판. 규칙(RunnerGame)과 화면·입력·소리를 잇고, 부딪힘·코인 같은 순간을 화면 효과로 바꾼다.
/// 메인 스레드에서만 쓴다. 그리는 동안 바뀌는 값은 @Published로 두지 않는다 (그리기 중 화면 갱신을 일으키지 않게).
final class GameSession {
    /// 러너 판정 상자. 캐릭터마다 그림 크기가 달라도 같은 조건으로 겨루게 고정한다.
    static let runnerWidth: Double = 24
    static let runnerHeight: Double = 40
    /// 러너 왼쪽 끝의 화면 x. 장애물을 볼 거리를 넉넉히 둔다.
    static let runnerX: CGFloat = 44
    /// 게임 중 캐릭터가 차지할 수 있는 크기 (pt). 판정 상자보다 조금 크게, 옆으로 긴 러너도 이 폭 안에 그린다.
    static let characterHeight: CGFloat = 46
    static let characterWidth: CGFloat = 40

    let game: RunnerGame
    private(set) var character: RunnerCharacter
    /// 사람이 하는 판. 아니면(점검 도구) 키를 받지 않고, 소리를 내지 않고, 기록도 남기지 않는다.
    private let live: Bool
    /// 키를 받을 창 (팝오버). 다른 창으로 가는 키는 건드리지 않는다.
    var window: () -> NSWindow? = { nil }
    /// 세션이 열린 뒤 흐른 시간 (그린 장면 기준).
    private var clock: Double = 0
    private var lastDate: Date?
    private var keyMonitor: Any?
    private var particles: [Particle] = []
    private var popups: [Popup] = []
    private var shake: CGFloat = 0
    private var flash: CGFloat = 0
    private var milestoneGlow: CGFloat = 0
    private var recordBanner: CGFloat = 0
    private var finished = false
    /// 캐릭터별 게임 배율. 서 있는 모습을 재서 정한다.
    private var scaleCache: (key: String, scale: CGFloat)?
    /// 판이 끝났을 때 바깥(순위 서버·말풍선)에 알린다.
    var onFinish: (RunnerGame) -> Void = { _ in }
    /// 게임 오버 화면에 덧붙일 순위 소식 ("전체 12위 · 340명"). 순위 서버 응답이 오면 바뀐다.
    var rankLine: String?
    /// 몇 번째 판인지. 앞 판의 순위 응답이 늦게 와 다음 판 화면에 붙지 않게 비교한다.
    private(set) var runID = 0
    /// 판을 시작할 때마다 최신 순위에서 앞에 있는 사람들을 받아 목표로 삼는다.
    var rivalSource: () -> [Rival] = { [] } {
        didSet { tracker = RivalTracker(rivals: rivalSource()) }
    }
    private var tracker = RivalTracker(rivals: [])
    /// 방금 앞지른 사람 (배너).
    private var overtaken: (name: String, life: CGFloat)?
    var onExit: () -> Void = {}

    init(character: RunnerCharacter, live: Bool = true) {
        self.character = character
        self.live = live
        var tuning = RunnerGame.Tuning()
        tuning.catalog = GameAssets.catalog(runnerHeight: Self.runnerHeight)
        game = RunnerGame(tuning: tuning, runnerWidth: Self.runnerWidth, runnerHeight: Self.runnerHeight,
                          best: live ? GameRecords.best : 0)
        if live { installKeys() }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func use(_ character: RunnerCharacter) { self.character = character }

    // MARK: 입력

    func press() {
        let wasOver = game.phase == .over
        game.press()
        if wasOver, game.phase == .playing { restarted() }
    }

    func release() { game.release() }

    /// 게임 중 팝오버 창으로 오는, 보조키 없는 키만 받는다. 다룬 키는 삼켜 경고음이 나지 않게 한다.
    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window != nil, event.window === self.window(),
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                      .subtracting([.function, .numericPad, .capsLock]).isEmpty
            else { return event }
            let down = event.type == .keyDown
            switch event.keyCode {
            case 49, 126, 13:   // 스페이스, ↑, W
                if down, !event.isARepeat { self.press() }
                if !down { self.release() }
                return nil
            case 125, 1:        // ↓, S
                self.game.setDuck(down)
                return nil
            case 53:            // esc
                if down { self.onExit() }
                return nil
            default:
                return event
            }
        }
    }

    private func restarted() {
        finished = false
        rankLine = nil
        runID += 1
        tracker = RivalTracker(rivals: rivalSource())
        overtaken = nil
        particles.removeAll()
        popups.removeAll()
        recordBanner = 0
    }

    // MARK: 한 프레임

    /// 시간을 보내고 일어난 일을 소리·효과로 바꾼다.
    func update(date: Date) {
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date
        clock += dt
        game.advance(by: dt)
        for event in game.drainEvents() { handle(event) }
        if game.phase == .playing {
            for rival in tracker.update(score: game.score) { pass(rival) }
        }

        let k = CGFloat(dt)
        shake = max(0, shake - k * 14)
        flash = max(0, flash - k * 6)
        milestoneGlow = max(0, milestoneGlow - k * 1.6)
        recordBanner = max(0, recordBanner - k * 0.55)
        if let current = overtaken { overtaken = current.life > k ? (current.name, current.life - k) : nil }
        for i in particles.indices {
            particles[i].velocity.y += particles[i].gravity * k
            particles[i].position.x += particles[i].velocity.x * k - CGFloat(game.phase == .playing ? game.speed : 0) * k * particles[i].drift
            particles[i].position.y += particles[i].velocity.y * k
            particles[i].life -= k
        }
        particles.removeAll { $0.life <= 0 }
        for i in popups.indices {
            popups[i].position.y += 26 * k
            popups[i].life -= k
        }
        popups.removeAll { $0.life <= 0 }
    }

    private func handle(_ event: RunnerGame.Event) {
        let feet = CGPoint(Self.runnerX + Self.runnerWidth / 2, 0)
        switch event {
        case .started:
            restarted()
        case .jumped:
            play(.jump)
            burst(at: feet, count: 5, color: NSColor(white: 0.85, alpha: 1), speed: 40, life: 0.35, drift: 1)
        case .landed:
            burst(at: feet, count: 4, color: NSColor(white: 0.85, alpha: 1), speed: 30, life: 0.3, drift: 1)
        case .coin(let id):
            play(.coin)
            if let coin = game.coins.first(where: { $0.id == id }) {
                let point = CGPoint(screenX(coin.x), CGFloat(coin.y))
                burst(at: point, count: 8, color: NSColor(hex: 0xFFD45E), speed: 70, life: 0.45, drift: 0.6)
                popups.append(Popup(text: "+\(game.tuning.coinValue)", position: point, life: 0.8))
            }
        case .milestone:
            play(.milestone)
            milestoneGlow = 1
        case .newRecord:
            play(.record)
            recordBanner = 1
        case .crashed:
            play(.hit)
            shake = 1
            flash = 1
            let center = CGPoint(Self.runnerX + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight / 2))
            burst(at: center, count: 12, color: .white, speed: 120, life: 0.55, drift: 0)
            if !finished {
                finished = true
                if live { GameRecords.finish(score: game.score) }
                onFinish(game)
            }
        }
    }

    private func play(_ effect: GameSound.Effect) {
        if live { GameSound.shared.play(effect) }
    }

    private func pass(_ rival: Rival) {
        play(.milestone)
        overtaken = (rival.name, 1.6)
        let center = CGPoint(Self.runnerX + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight))
        burst(at: center, count: 10, color: NSColor(hex: 0xFFD45E), speed: 90, life: 0.6, drift: 0.4)
    }

    /// 다음 목표 깃발의 화면 x. 그 지점에 닿으면 점수가 목표를 넘는다 (코인을 먹으면 깃발이 당겨진다).
    private func flagX() -> CGFloat? {
        guard game.phase == .playing, let next = tracker.next else { return nil }
        let need = Double(next.score + 1 - game.coinsTaken * game.tuning.coinValue) / game.tuning.scorePerPoint
        return screenX(need) + CGFloat(Self.runnerWidth) / 2
    }

    // MARK: 화면 효과

    /// 바닥 위 높이(y 위로)로 잰 점 주변에 작은 점을 흩뿌린다.
    private func burst(at point: CGPoint, count: Int, color: NSColor, speed: CGFloat, life: CGFloat, drift: CGFloat) {
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi + .pi * 0.05 + CGFloat.random(in: -0.2...0.2)
            let v = speed * CGFloat.random(in: 0.6...1.1)
            particles.append(Particle(position: point, velocity: CGPoint(-cos(angle) * v, sin(angle) * v),
                                      gravity: -220, life: life * CGFloat.random(in: 0.7...1), total: life,
                                      color: color, size: CGFloat.random(in: 1.4...2.6), drift: drift))
        }
    }

    private struct Particle {
        var position: CGPoint   // x는 화면, y는 바닥 위 높이
        var velocity: CGPoint
        var gravity: CGFloat
        var life: CGFloat
        let total: CGFloat
        let color: NSColor
        let size: CGFloat
        /// 땅을 따라 뒤로 흘러가는 정도 (먼지 1, 터지는 별 0).
        let drift: CGFloat
    }

    private struct Popup {
        let text: String
        var position: CGPoint
        var life: CGFloat
    }

    // MARK: 그리기

    func screenX(_ worldX: Double) -> CGFloat { Self.runnerX + CGFloat(worldX - game.distance) }

    /// 무대가 열린 뒤 게임 화면으로 넘어가는 정도 (0~1). 러너가 작아지며 왼쪽으로 간다.
    var entrance: CGFloat {
        let t = min(1, CGFloat(clock) / 0.45)
        return t * t * (3 - 2 * t)
    }

    /// 화면 흔들림. 부딪힌 순간에만.
    var shakeOffset: CGPoint {
        guard shake > 0 else { return .zero }
        let a = shake * shake * 4
        return CGPoint(CGFloat.random(in: -a...a), CGFloat.random(in: -a...a))
    }

    /// 장애물, 코인, 러너, 파티클. 배경은 무대가 먼저 그린다.
    func drawWorld(_ cg: CGContext, size: CGSize, groundY: CGFloat, stageAnchorX: CGFloat, stageScale: CGFloat,
                   theme: SpriteTheme, time: Double) {
        let ground = { (height: Double) in groundY - CGFloat(height) }

        // 코인
        for coin in game.coins where !coin.taken {
            let x = screenX(coin.x)
            guard x > -20, x < size.width + 20, let image = GameSprite.coin.frame(at: time + coin.x * 0.01) else { continue }
            let bob = CGFloat(sin(time * 5 + coin.x * 0.05)) * 1.5
            let s = GameSprite.pixelScale
            let rect = CGRect(x: x - 9 * s, y: ground(coin.y) - 9 * s + bob, width: 18 * s, height: 18 * s)
            GameAssets.draw(image, in: rect, cg)
        }

        // 장애물
        for obstacle in game.obstacles {
            guard let sprite = GameSprite(rawValue: obstacle.kind.id) else { continue }
            let left = screenX(obstacle.x)
            guard left < size.width + 40, left + CGFloat(obstacle.width) > -40 else { continue }
            let content = sprite.content
            let s = GameSprite.pixelScale
            let frames = sprite.frames
            let phase = time + Double(obstacle.id) * 0.13
            for k in 0..<obstacle.count {
                guard let image = frames.isEmpty ? nil : sprite.frame(at: phase) else { continue }
                // 판정 상자(그림 영역)에 맞춰 타일 전체를 놓는다
                let boxLeft = left + CGFloat(k) * CGFloat(obstacle.kind.width)
                let boxBottom = ground(obstacle.y)
                let rect = CGRect(x: boxLeft - content.minX * s,
                                  y: boxBottom - content.maxY * s,
                                  width: CGFloat(image.width) * s, height: CGFloat(image.height) * s)
                GameAssets.draw(image, in: rect, cg)
            }
            if obstacle.id == game.crashedInto {
                cg.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.8).cgColor)
                cg.setLineWidth(1.5)
                cg.stroke(CGRect(x: left - 2, y: ground(obstacle.y) - CGFloat(obstacle.height) - 2,
                                 width: CGFloat(obstacle.width) + 4, height: CGFloat(obstacle.height) + 4))
            }
        }

        // 다음 목표 깃발
        if let x = flagX(), x > -10, x < size.width + 10 {
            cg.setStrokeColor(NSColor(white: 0.92, alpha: 0.9).cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x, groundY))
            cg.addLine(to: CGPoint(x, groundY - 46))
            cg.strokePath()
            let wave = CGFloat(sin(time * 8)) * 1.5
            cg.setFillColor(NSColor(hex: 0xFF6B5E).cgColor)
            cg.move(to: CGPoint(x, groundY - 46))
            cg.addLine(to: CGPoint(x + 15, groundY - 41 + wave))
            cg.addLine(to: CGPoint(x, groundY - 36))
            cg.closePath()
            cg.fillPath()
        }

        drawRunner(cg, groundY: groundY, stageAnchorX: stageAnchorX, stageScale: stageScale, theme: theme, time: time)

        // 파티클
        for p in particles {
            let alpha = max(0, min(1, p.life / p.total))
            cg.setFillColor(p.color.withAlphaComponent(alpha).cgColor)
            let r = p.size
            cg.fillEllipse(in: CGRect(x: p.position.x - r, y: ground(Double(p.position.y)) - r, width: r * 2, height: r * 2))
        }

        // 빠를수록 바람이 보인다
        if game.phase == .playing, game.speed > 400 {
            let strength = CGFloat((game.speed - 400) / (game.tuning.maxSpeed - 400))
            cg.setStrokeColor(NSColor.white.withAlphaComponent(0.18 + 0.2 * strength).cgColor)
            cg.setLineWidth(1)
            cg.setLineCap(.round)
            for i in 0..<5 {
                let span = size.width + 80
                let raw = Double(i) * 97.3 - game.distance * 1.6
                let x = CGFloat(raw - floor(raw / Double(span)) * Double(span)) - 40
                let y = 18 + CGFloat(i) * (groundY - 40) / 5
                cg.move(to: CGPoint(x, y))
                cg.addLine(to: CGPoint(x + 18 + 20 * strength, y))
            }
            cg.strokePath()
        }

        if flash > 0 {
            cg.setFillColor(NSColor.white.withAlphaComponent(flash * 0.35).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func drawRunner(_ cg: CGContext, groundY: CGFloat, stageAnchorX: CGFloat, stageScale: CGFloat,
                            theme: SpriteTheme, time: Double) {
        let rig = character.rig
        var frame: MotionFrame
        switch game.phase {
        case .ready:
            frame = MotionFrame(pose: CharacterPose(activity: .stand, phase: CGFloat(time / 2.4)))
        case .playing where !game.isOnGround:
            frame = MotionFrame(pose: CharacterPose(activity: .run, phase: 0.62, speed: 1.2))
            // 오를 때 살짝 들고, 내려올 때 숙인다
            frame.transform.rotation = CGFloat(-game.velocityY / game.tuning.jumpVelocity) * 0.12
        case .playing:
            // 보폭 70pt마다 한 걸음 주기
            frame = MotionFrame(pose: CharacterPose(activity: .run, phase: CGFloat(game.distance / 70), speed: 1.25))
            if game.isDucking { frame.transform.squash = 0.6 }
        case .over:
            frame = MotionFrame(pose: CharacterPose(activity: .sit, phase: CGFloat(time / 1.1), mouthOpen: true))
            frame.effects = [.dizzyStars(CGFloat(time.truncatingRemainder(dividingBy: 1)))]
        }

        let gameScale = scale(for: rig)
        let e = entrance
        let scale = stageScale + (gameScale - stageScale) * e
        let center = stageAnchorX + (Self.runnerX + CGFloat(Self.runnerWidth) / 2 - stageAnchorX) * e
        let feet = groundY - CGFloat(game.runnerY)

        var scene = CharacterScene(rig: rig, pose: frame.pose, transform: frame.transform)
        // 무대 높이 안으로 (뛰는 동안 머리가 잘리지 않게)
        let origin = CGPoint(center - FittedRig.targetCenterX * scale, feet - Stage.ground * scale)
        scene.fit(verticallyIn: (-origin.y / scale + 0.4)...((groundY + 15 - origin.y) / scale))

        // 그림자
        let lift = CGFloat(game.runnerY)
        let shadowW = CGFloat(Self.runnerWidth) * 1.3 * (1 - min(lift / 120, 0.6))
        cg.setFillColor(NSColor.black.withAlphaComponent(0.25 * (1 - min(lift / 90, 0.8))).cgColor)
        cg.fillEllipse(in: CGRect(x: center - shadowW / 2, y: groundY - 2.5, width: shadowW, height: 5))

        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: scale, y: scale)
        let look = CharacterLook(rich: true, palette: theme.richPalette(rig.palette, phase: CGFloat(time / 6)),
                                 tint: .white, outline: 0.36)
        scene.draw(in: cg, look: look)
        for effect in frame.effects { effect.draw(in: cg, around: scene.placedBounds, tint: .white) }
        cg.restoreGState()
    }

    /// 서 있는 모습이 characterHeight × characterWidth 안에 들어가는 배율. 고양이·고래처럼 옆으로 긴 러너가
    /// 판정 상자보다 훨씬 크게 그려져 닿지 않았는데 부딪힌 것처럼 보이지 않게 한다.
    private func scale(for rig: CharacterRig) -> CGFloat {
        if let cached = scaleCache, cached.key == character.key { return cached.scale }
        let bounds = CharacterScene(rig: rig, pose: CharacterPose(activity: .stand)).bounds
        let scale = bounds.isNull ? Self.characterHeight / FittedRig.targetHeight
            : min(Self.characterHeight / max(bounds.height, 1), Self.characterWidth / max(bounds.width, 1))
        scaleCache = (character.key, scale)
        return scale
    }

    // MARK: 점수판

    /// 무대 위 글자. 그리기 컨텍스트가 바로 그리도록 위치와 함께 넘긴다.
    struct Label {
        let text: Text
        let position: CGPoint
        var anchor: UnitPoint = .center
    }

    struct Panel {
        let rect: CGRect
    }

    func overlay(size: CGSize) -> (panels: [Panel], labels: [Label]) {
        var labels: [Label] = []
        var panels: [Panel] = []
        let digits = Font.system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
        let small = Font.system(size: 10.5, weight: .medium).monospacedDigit()
        let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

        if game.phase != .ready {
            let glow = milestoneGlow > 0 && Int(milestoneGlow * 10) % 2 == 0
            labels.append(Label(text: Text(String(format: "%05d", game.score)).font(digits)
                                    .foregroundColor(glow ? gold : .white),
                                position: CGPoint(12, 10), anchor: .topLeading))
            labels.append(Label(text: Text("최고 \(max(game.best, game.score))").font(small)
                                    .foregroundColor(.white.opacity(0.75)),
                                position: CGPoint(12, 29), anchor: .topLeading))
            if game.coinsTaken > 0 {
                labels.append(Label(text: Text("코인 \(game.coinsTaken)").font(small).foregroundColor(gold.opacity(0.9)),
                                    position: CGPoint(12, 43), anchor: .topLeading))
            }
        }
        for popup in popups {
            labels.append(Label(text: Text(popup.text).font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundColor(gold.opacity(Double(min(1, popup.life * 2)))),
                                position: CGPoint(popup.position.x, (size.height - 15) - popup.position.y - 14)))
        }
        if game.phase == .playing, let next = tracker.next {
            // 오른쪽 위 단추와 겹치지 않게 긴 닉네임은 자른다
            let name = next.name.count > 6 ? next.name.prefix(6) + "…" : Substring(next.name)
            labels.append(Label(text: Text("목표 \(String(name)) \(next.score) (-\(max(0, next.score + 1 - game.score)))")
                                    .font(small).foregroundColor(.white.opacity(0.85)),
                                position: CGPoint(size.width / 2, 12)))
            if let x = flagX(), x > 0, x < size.width {
                labels.append(Label(text: Text(next.name).font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.white),
                                    position: CGPoint(x + 8, size.height - 15 - 56)))
            }
        }
        if let overtaken, game.phase == .playing {
            labels.append(Label(text: Text("\(overtaken.name) 추월!").font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(gold.opacity(Double(min(1, overtaken.life * 2)))),
                                position: CGPoint(size.width / 2, 34)))
        }
        if recordBanner > 0, game.phase == .playing {
            labels.append(Label(text: Text("신기록!").font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundColor(gold.opacity(Double(min(1, recordBanner * 3)))),
                                position: CGPoint(size.width / 2, overtaken == nil ? 34 : 52)))
        }

        let center = CGPoint(size.width / 2, size.height / 2 - 12)
        switch game.phase {
        case .ready where entrance >= 1:
            panels.append(Panel(rect: CGRect(x: center.x - 112, y: center.y - 34, width: 224, height: 62)))
            labels.append(Label(text: Text("토큰 러너").font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y - 18)))
            labels.append(Label(text: Text("스페이스·클릭으로 시작").font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9)), position: CGPoint(center.x, center.y)))
            let best = game.best > 0 ? "최고 \(game.best)  ·  " : ""
            labels.append(Label(text: Text("\(best)길게 누르면 높이, ↓ 숙이기").font(small)
                                    .foregroundColor(.white.opacity(0.65)), position: CGPoint(center.x, center.y + 16)))
        case .over:
            let extra: CGFloat = rankLine == nil ? 0 : 14
            panels.append(Panel(rect: CGRect(x: center.x - 112, y: center.y - 34, width: 224, height: 66 + extra)))
            let title = game.isNewRecord ? "신기록!" : "앗, 부딪혔다"
            labels.append(Label(text: Text(title).font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundColor(game.isNewRecord ? gold : .white),
                                position: CGPoint(center.x, center.y - 19)))
            labels.append(Label(text: Text("\(game.score)점").font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y + 1)))
            if let rankLine {
                labels.append(Label(text: Text(rankLine).font(small.weight(.semibold)).foregroundColor(gold),
                                    position: CGPoint(center.x, center.y + 20)))
            }
            labels.append(Label(text: Text("최고 \(game.best)  ·  스페이스·클릭으로 다시").font(small)
                                    .foregroundColor(.white.opacity(0.7)), position: CGPoint(center.x, center.y + 21 + extra)))
        default:
            break
        }
        return (panels, labels)
    }
}

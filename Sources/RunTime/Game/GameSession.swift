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
    private var resignObserver: Any?
    private var particles: [Particle] = []
    private var popups: [Popup] = []
    private var shake: CGFloat = 0
    private var flash: CGFloat = 0
    private var milestoneGlow: CGFloat = 0
    private var recordBanner: CGFloat = 0
    private var finished = false
    /// 캐릭터별 게임 배율. 서 있는 모습을 재서 정한다.
    private var scaleCache: [String: CGFloat] = [:]
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
    /// 이번 판 기록 (미션). 판이 끝나면 지갑에 한 번 넣는다.
    private var jumps = 0
    private var nearMisses = 0
    private var credited = false
    /// Claude가 일하는 동안 한 판이면 코인을 두 배로 준다 (기다리는 동안 한 판).
    private(set) var boosted = false
    /// 꼬리를 그릴 지난 자리들 (화면 x, 바닥 위 높이). 땅이 흐르는 만큼 뒤로 민다.
    private var trail: [CGPoint] = []
    /// 점수판으로 날아가는 코인 (화면 좌표).
    private struct CoinFlyer {
        let from: CGPoint
        var t: CGFloat = 0
    }
    private var coinFlyers: [CoinFlyer] = []
    /// 마지막으로 그린 땅 높이 (코인이 날아오를 자리를 화면 좌표로 바꿀 때).
    private var groundY: CGFloat = 135
    /// 착지 반동 (1에서 0으로).
    private var landBounce: CGFloat = 0
    /// 하늘 구간. 500점마다 다음 하늘로 넘어가고, 1.5초 동안 섞어 바꾼다.
    private var skyFrom = 0
    private var skyTo: Int?
    private var skyBlend: CGFloat = 1
    private var zoneBanner: (text: String, life: CGFloat)?
    /// 게임 밖에서 온 소식 (Claude 작업 끝). 판을 멈추지 않고 아래쪽에 잠깐 띄운다.
    private var notice: (text: String, life: CGFloat)?
    var onExit: () -> Void = {}
    /// 이 Mac의 최고 판. 고스트와 겨룰 때 같은 코스와 그때 움직임을 다시 돌린다.
    var savedGhost: GhostRecord?
    /// 지금 겨루는 고스트와 그 고스트를 그릴 러너 (그 판을 달린 러너, 이 Mac에 없으면 유령).
    private(set) var raceTarget: GhostRecord?
    private var ghost: GhostRunner?
    private var ghostCharacter = Runner.ghost.character
    /// 고스트와 겨루는 판. 코스를 미리 알고 하는 판이라 기록과 순위에 넣지 않는다.
    private(set) var isRace = false

    init(character: RunnerCharacter, live: Bool = true) {
        self.character = character
        self.live = live
        var tuning = RunnerGame.Tuning()
        tuning.catalog = GameAssets.catalog(runnerHeight: Self.runnerHeight)
        game = RunnerGame(tuning: tuning, runnerWidth: Self.runnerWidth, runnerHeight: Self.runnerHeight,
                          best: live ? GameRecords.best : 0)
        if live {
            savedGhost = GhostStore.load(for: game)
            TopGhost.all.refresh(for: game)
            TopGhost.week.refresh(for: game)
            installKeys()
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func use(_ character: RunnerCharacter) { self.character = character }

    // MARK: 입력

    func press() {
        let wasOver = game.phase == .over
        if game.phase != .playing {
            isRace = false
            ghost = nil
            if live { game.setAbilities(GameWallet.shared.abilities) }
        }
        game.press()
        if wasOver, game.phase == .playing { restarted() }
    }

    /// 고스트 판과 같은 코스에서 그 고스트와 함께 달린다.
    func startRace(_ record: GhostRecord?) {
        guard let record, let seed = record.seedValue, game.phase != .playing else { return }
        game.prepare(seed: seed)
        guard game.phase == .ready else { return }   // 부딪힌 직전이라 아직 다시 시작할 수 없음
        ghost = GhostRunner(tuning: game.tuning, runnerWidth: Self.runnerWidth, runnerHeight: Self.runnerHeight,
                            seed: seed, inputs: record.inputs, abilities: record.abilities ?? RunnerGame.Abilities())
        if live { game.setAbilities(GameWallet.shared.abilities) }
        isRace = true
        raceTarget = record
        ghostCharacter = AppSettings.character(forRunnerID: record.runner) ?? Runner.ghost.character
        game.press()
        game.release()
    }

    /// 주간 1위 고스트. 전체 1위와 같은 판이면 두 번 보이지 않게 뺀다.
    var weekGhost: GhostRecord? {
        guard let week = TopGhost.week.record else { return nil }
        let all = TopGhost.all.record
        return all?.seed == week.seed && all?.score == week.score ? nil : week
    }

    /// 지금 점수에서 고스트 판의 최종 점수를 뺀 값 (겨루는 중에만). 넘으면 이긴다.
    var raceLead: Int? {
        guard isRace, let raceTarget else { return nil }
        return game.score - raceTarget.score
    }


    func release() { game.release() }

    /// 게임 중 팝오버 창으로 오는, 보조키 없는 키만 받는다. 다룬 키는 삼켜 경고음이 나지 않게 한다.
    /// 누른 키를 모두 놓은 것으로 한다. 키를 누른 채 다른 창을 누르면 뗀 신호가 오지 않아 계속 움직이거나 숙인 채 남는다.
    func releaseAllKeys() {
        game.setMove(back: false, forward: false)
        game.setDuck(false)
        game.release()
    }

    private func installKeys() {
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil,
                                                                queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === self.window() else { return }
            self.releaseAllKeys()
        }
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
            case 123, 0:        // ←, A
                self.game.setMove(back: down)
                return nil
            case 124, 2:        // →, D
                self.game.setMove(forward: down)
                return nil
            case 5, 18, 19 where self.game.phase != .playing:   // G 내 고스트, 1 전체 1위, 2 주간 1위 고스트
                if down, !event.isARepeat {
                    switch event.keyCode {
                    case 5: self.startRace(self.savedGhost)
                    case 18: self.startRace(TopGhost.all.record)
                    default: self.startRace(self.weekGhost)
                    }
                }
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
        tracker = RivalTracker(rivals: isRace ? [] : rivalSource())
        overtaken = nil
        particles.removeAll()
        popups.removeAll()
        recordBanner = 0
        jumps = 0
        nearMisses = 0
        credited = false
        boosted = false
        trail.removeAll()
        skyTo = nil
        zoneBanner = nil
    }

    // MARK: 한 프레임

    /// 시간을 보내고 일어난 일을 소리·효과로 바꾼다.
    func update(date: Date) {
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date
        clock += dt
        game.advance(by: dt)
        ghost?.advance(by: dt)
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
        if let current = notice { notice = current.life > k ? (current.text, current.life - k) : nil }
        if let current = zoneBanner { zoneBanner = current.life > k ? (current.text, current.life - k) : nil }
        skyBlend = min(1, skyBlend + k / 1.5)
        updateTrail(k)
        landBounce = max(0, landBounce - k * 7)
        for i in coinFlyers.indices { coinFlyers[i].t += k / 0.45 }
        coinFlyers.removeAll { $0.t >= 1 }
        if live, game.phase == .playing, !boosted, UsageEngine.isClaudeWorking { boosted = true }
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
        let feet = CGPoint(runnerLeft + Self.runnerWidth / 2, 0)
        switch event {
        case .started:
            restarted()
        case .jumped:
            play(.jump)
            jumps += 1
            burst(at: feet, count: 5, colors: dustColors, speed: 40, life: 0.35, drift: 1)
        case .landed:
            burst(at: feet, count: 4, colors: dustColors, speed: 30, life: 0.3, drift: 1)
            landBounce = 1
        case .coin(let id):
            play(.coin)
            if let coin = game.coins.first(where: { $0.id == id }) {
                let point = CGPoint(screenX(coin.x), CGFloat(coin.y))
                burst(at: point, count: 8, color: NSColor(hex: 0xFFD45E), speed: 70, life: 0.45, drift: 0.6)
                coinFlyers.append(CoinFlyer(from: CGPoint(screenX(coin.x), groundY - CGFloat(coin.y))))
                popups.append(Popup(text: "+\(game.tuning.coinValue)", position: point, life: 0.8))
            }
        case .milestone:
            play(.milestone)
            milestoneGlow = 1
        case .airJumped:
            play(.airjump)
            jumps += 1
            let feet = CGPoint(runnerLeft + Self.runnerWidth / 2, CGFloat(game.runnerY))
            burst(at: feet, count: 10, colors: [.white, NSColor(hex: 0x8FD3FF)], shape: .spark, speed: 70, life: 0.4,
                  drift: 0.4, spread: 2)
        case .shieldBroke:
            play(.shield)
            shake = 0.5
            let center = CGPoint(runnerLeft + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight / 2))
            burst(at: center, count: 14, colors: [NSColor(hex: 0x8FD3FF), .white], shape: .spark, speed: 140, life: 0.6,
                  drift: 0, spread: 2)
            popups.append(Popup(text: "보호막!", position: center, life: 0.8))
        case .nearMiss:
            play(.nearmiss)
            nearMisses += 1
            let point = CGPoint(runnerLeft + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight * 0.6))
            burst(at: point, count: 6, color: NSColor(hex: 0x8FD3FF), speed: 60, life: 0.4, drift: 0.5)
            popups.append(Popup(text: "아슬!", position: point, life: 0.7))
        case .newRecord where !isRace:
            play(.record)
            recordBanner = 1
        case .newRecord:
            break
        case .crashed:
            play(.hit)
            shake = 1
            flash = 1
            let center = CGPoint(runnerLeft + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight / 2))
            crashBurst(at: center)
            let missionDone = creditRun()
            // 부딪힌 소리 뒤에 짧은 음악 하나: 이겼으면 팡파르, 미션을 채웠으면 미션 음악, 아니면 게임 오버
            let won = isRace ? (raceLead ?? 0) > 0 : game.isNewRecord
            let jingle: GameSound.Effect = won ? .fanfare : missionDone ? .mission : .gameover
            let run = runID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.runID == run, self.game.phase == .over else { return }
                self.play(jingle)
            }
            if !finished, !isRace {
                finished = true
                if live {
                    GameRecords.finish(score: game.score)
                    if game.score > savedGhost?.score ?? 0 {
                        let record = GhostStore.record(of: game, runner: AppSettings.shared.runnerID)
                        if GhostStore.save(record) { savedGhost = record }
                    }
                }
                onFinish(game)
            }
        }
    }

    /// 판이 끝나면 코인과 미션을 지갑에 넣는다. 고스트와 겨룬 판도 넣는다 (꾸미기에만 쓰는 코인이라).
    /// 미션을 새로 채웠으면 true.
    private func creditRun() -> Bool {
        guard live, !credited else { return false }
        credited = true
        let run = DailyMissions.Run(coins: game.coinsTaken, nearMisses: nearMisses, score: game.score, jumps: jumps,
                                    wonRace: (raceLead ?? 0) > 0)
        let completed = GameWallet.shared.finishRun(run, bonusCoins: boosted ? game.coinsTaken : 0)
        if !completed.isEmpty {
            let reward = completed.reduce(0) { $0 + $1.reward }
            announce("미션 완료: \(completed.map(\.title).joined(separator: ", ")) +\(reward)", sound: false)
        }
        return !completed.isEmpty
    }

    func announce(_ text: String, sound: Bool = true) {
        notice = (text, 3.5)
        if sound { play(.record) }
    }

    private func play(_ effect: GameSound.Effect) {
        if live { GameSound.shared.play(effect) }
    }

    private func pass(_ rival: Rival) {
        play(.milestone)
        overtaken = (rival.name, 1.6)
        let center = CGPoint(runnerLeft + Self.runnerWidth / 2, CGFloat(game.runnerY + Self.runnerHeight))
        burst(at: center, count: 10, color: NSColor(hex: 0xFFD45E), speed: 90, life: 0.6, drift: 0.4)
    }

    /// 다음 목표 깃발의 화면 x. 러너가 닿으면 점수가 목표를 넘는다 (코인을 먹으면 깃발이 당겨진다).
    /// 점수는 거리로만 세므로 앞뒤로 움직인 만큼 깃발도 같이 옮겨, 러너가 닿는 때와 넘는 때를 맞춘다.
    private func flagX() -> CGFloat? {
        guard game.phase == .playing, let next = tracker.next else { return nil }
        let need = Double(next.score + 1 - game.coinsTaken * game.tuning.coinValue) / game.tuning.scorePerPoint
        return screenX(need) + CGFloat(game.runnerOffset) + CGFloat(Self.runnerWidth) / 2
    }

    // MARK: 하늘 구간

    private static let zoneNames = ["새벽", "낮", "노을", "밤", "우주"]
    private static let zoneHours = [6, 12, 18, 22]
    /// 우주에 닿으면 더 바뀌지 않는다.
    static let zoneScore = 500

    private static func zone(hour: Int) -> Int {
        switch hour {
        case 5..<8: 0
        case 8..<17: 1
        case 17..<20: 2
        default: 3
        }
    }

    private static func sky(zone: Int) -> Sky {
        zone >= zoneHours.count ? Sky.at(hour: 0, space: true) : Sky.at(hour: zoneHours[zone], space: false)
    }

    /// 지금 그릴 하늘. 지금 시각의 하늘에서 시작해 점수가 오를수록 다음 하늘로 간다.
    func sky(hour: Int) -> Sky {
        let start = Self.zone(hour: hour)
        let target = game.phase == .ready ? start : min(start + game.score / Self.zoneScore, Self.zoneNames.count - 1)
        if skyTo == nil {
            skyFrom = target
            skyTo = target
        } else if target != skyTo {
            skyFrom = skyTo ?? target
            skyTo = target
            skyBlend = 0
            if game.phase == .playing {
                zoneBanner = ("\(Self.zoneNames[target]) 구간", 2)
                play(.record)
            }
        }
        let from = Self.sky(zone: skyFrom), to = Self.sky(zone: skyTo ?? target)
        let t = skyBlend * skyBlend * (3 - 2 * skyBlend)
        return t >= 1 ? to : from.mixed(with: to, t)
    }

    static func fillHeart(_ cg: CGContext, at c: CGPoint, size s: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(c.x, c.y + s * 0.35))
        path.addCurve(to: CGPoint(c.x - s * 0.5, c.y - s * 0.1), control1: CGPoint(c.x - s * 0.1, c.y + s * 0.1),
                      control2: CGPoint(c.x - s * 0.5, c.y + s * 0.15))
        path.addArc(center: CGPoint(c.x - s * 0.25, c.y - s * 0.12), radius: s * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addArc(center: CGPoint(c.x + s * 0.25, c.y - s * 0.12), radius: s * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addCurve(to: CGPoint(c.x, c.y + s * 0.35), control1: CGPoint(c.x + s * 0.5, c.y + s * 0.15),
                      control2: CGPoint(c.x + s * 0.1, c.y + s * 0.1))
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    // MARK: 능력

    /// 보호막 방울과 글라이드 날개. 내 러너에만.
    private func drawAbilities(_ cg: CGContext, groundY: CGFloat, time: Double) {
        guard game.phase == .playing, entrance >= 1 else { return }
        let center = CGPoint(runnerLeft + CGFloat(Self.runnerWidth) / 2, groundY - CGFloat(game.runnerY + Self.runnerHeight / 2))
        cg.saveGState()
        if game.shieldsLeft > 0 {
            let pulse = 1 + 0.04 * CGFloat(sin(time * 5))
            for k in 0..<game.shieldsLeft {
                let r = (27 + CGFloat(k) * 4) * pulse
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                cg.setFillColor(NSColor(hex: 0x8FD3FF).withAlphaComponent(k == 0 ? 0.08 : 0).cgColor)
                cg.fillEllipse(in: rect)
                cg.setStrokeColor(NSColor(hex: 0x8FD3FF).withAlphaComponent(0.55 - CGFloat(k) * 0.15).cgColor)
                cg.setLineWidth(1.2)
                cg.strokeEllipse(in: rect)
            }
        }
        if game.isGliding {
            // 머리 위 낙하산
            let top = CGPoint(center.x - 2, center.y - 40)
            let canopy = CGMutablePath()
            canopy.addArc(center: CGPoint(top.x, top.y + 6), radius: 17, startAngle: .pi * 1.08, endAngle: .pi * 1.92,
                          clockwise: false)
            canopy.closeSubpath()
            cg.setFillColor(NSColor(hex: 0xFF8FB8).withAlphaComponent(0.9).cgColor)
            cg.addPath(canopy)
            cg.fillPath()
            cg.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(0.8)
            for dx in [-14.0, 0, 14] {
                cg.move(to: CGPoint(top.x + CGFloat(dx), top.y + 1))
                cg.addLine(to: CGPoint(center.x - 2, center.y - 14))
            }
            cg.strokePath()
        }
        cg.restoreGState()
    }

    // MARK: 꾸미기

    private var dustColors: [NSColor] {
        switch GameWallet.shared.equipped(.dust) {
        case .rainbowDust: SpriteEffects.rainbow
        case let dust?: [dust.color]
        case nil: [NSColor(white: 0.85, alpha: 1)]
        }
    }

    /// 부딪힌 순간. 기본은 흰 별, 상점 효과를 달면 그 모양으로 터진다.
    private func crashBurst(at center: CGPoint) {
        switch GameWallet.shared.equipped(.crash) {
        case .fireworksCrash:
            for (k, dx) in [-18.0, 0, 20].enumerated() {
                let point = CGPoint(center.x + CGFloat(dx), center.y + 18 + CGFloat(k % 2) * 10)
                burst(at: point, count: 14, colors: SpriteEffects.rainbow.shuffled(), shape: .spark, speed: 110,
                      life: 0.9, drift: 0, spread: 2)
            }
        case .heartCrash:
            burst(at: center, count: 12, colors: [NSColor(hex: 0xFF8FB8), NSColor(hex: 0xFF5C8A)], shape: .heart,
                  speed: 120, life: 0.9, drift: 0, spread: 2, size: 2.2...3.4)
        case .coinCrash:
            burst(at: center, count: 16, colors: [.white], shape: .coin, speed: 170, life: 1.1, drift: 0.3,
                  size: 1.6...2.4)
        default:
            burst(at: center, count: 12, color: .white, speed: 120, life: 0.55, drift: 0)
        }
    }

    private func updateTrail(_ k: CGFloat) {
        guard game.phase == .playing, GameWallet.shared.equipped(.trail) != nil else {
            if !trail.isEmpty { trail.removeFirst() }
            return
        }
        let shift = CGFloat(game.speed) * k
        for i in trail.indices { trail[i].x -= shift }
        let height = Self.runnerHeight * (game.isDucking ? 0.3 : 0.45)
        trail.append(CGPoint(runnerLeft + 2, CGFloat(game.runnerY + height)))
        if trail.count > 22 { trail.removeFirst(trail.count - 22) }
    }

    private func drawTrail(_ cg: CGContext, groundY: CGFloat, time: Double) {
        guard let item = GameWallet.shared.equipped(.trail), trail.count > 1 else { return }
        let points = trail.map { CGPoint($0.x, groundY - $0.y) }
        cg.saveGState()
        cg.setLineCap(.round)
        switch item {
        case .rainbowTrail:
            for (band, color) in SpriteEffects.rainbow.enumerated() {
                let dy = (CGFloat(band) - 2.5) * 2.2
                for i in 1..<points.count {
                    let t = CGFloat(i) / CGFloat(points.count)
                    cg.setStrokeColor(color.withAlphaComponent(0.85 * t).cgColor)
                    cg.setLineWidth(2.4)
                    cg.move(to: CGPoint(points[i - 1].x, points[i - 1].y + dy))
                    cg.addLine(to: CGPoint(points[i].x, points[i].y + dy))
                    cg.strokePath()
                }
            }
        case .cometTrail:
            for i in 1..<points.count {
                let t = CGFloat(i) / CGFloat(points.count)
                cg.setStrokeColor(item.color.withAlphaComponent(0.7 * t).cgColor)
                cg.setLineWidth(1 + 7 * t)
                cg.move(to: points[i - 1])
                cg.addLine(to: points[i])
                cg.strokePath()
            }
        case .fireTrail:
            // 꼬리 쪽으로 갈수록 노랗고 작아지며 흔들린다
            for (i, point) in points.enumerated() {
                let t = CGFloat(i) / CGFloat(points.count)
                let flicker = CGFloat(sin(time * 23 + Double(i) * 1.7)) * 1.2
                let r = 1 + 4 * t
                let color = NSColor(hex: 0xFFE14D).blended(withFraction: t, of: NSColor(hex: 0xFF5A1F)) ?? item.color
                cg.setFillColor(color.withAlphaComponent(0.25 + 0.6 * t).cgColor)
                cg.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r + flicker, width: r * 2, height: r * 2))
            }
        case .noteTrail, .heartTrail:
            for (i, point) in points.enumerated() where i % 5 == 1 {
                let t = CGFloat(i) / CGFloat(points.count)
                let bob = CGFloat(sin(time * 6 + Double(i))) * 3
                let p = CGPoint(point.x, point.y - 6 + bob)
                let color = item.color.withAlphaComponent(0.3 + 0.7 * t)
                if item == .heartTrail {
                    Self.fillHeart(cg, at: p, size: 4 + 3 * t, color: color)
                } else {
                    // 음표: 기운 머리와 기둥
                    let s = 0.8 + 0.5 * t
                    cg.setFillColor(color.cgColor)
                    cg.fillEllipse(in: CGRect(x: p.x - 2.4 * s, y: p.y + 1.5 * s, width: 3.6 * s, height: 2.6 * s))
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(1.1 * s)
                    cg.move(to: CGPoint(p.x + 1.1 * s, p.y + 2.6 * s))
                    cg.addLine(to: CGPoint(p.x + 1.1 * s, p.y - 4 * s))
                    cg.addLine(to: CGPoint(p.x + 3.2 * s, p.y - 2.6 * s))
                    cg.strokePath()
                }
            }
        default:
            for (i, point) in points.enumerated() where i % 3 == 0 {
                let t = CGFloat(i) / CGFloat(points.count)
                let twinkle = 0.7 + 0.3 * CGFloat(sin(time * 9 + Double(i)))
                SpriteEffects.sparkle(cg, at: point, radius: (1.5 + 3 * t) * twinkle, color: item.color.withAlphaComponent(t))
            }
        }
        cg.restoreGState()
    }

    // MARK: 화면 효과

    /// 바닥 위 높이(y 위로)로 잰 점 주변에 작은 점을 흩뿌린다.
    private func burst(at point: CGPoint, count: Int, color: NSColor, speed: CGFloat, life: CGFloat, drift: CGFloat) {
        burst(at: point, count: count, colors: [color], speed: speed, life: life, drift: drift)
    }

    /// `spread`가 1이면 위쪽 반원, 2면 사방으로 흩어진다.
    private func burst(at point: CGPoint, count: Int, colors: [NSColor], shape: Particle.Shape = .dot, speed: CGFloat,
                       life: CGFloat, drift: CGFloat, spread: CGFloat = 1, size: ClosedRange<CGFloat> = 1.4...2.6) {
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * spread + .pi * 0.05 + CGFloat.random(in: -0.2...0.2)
            let v = speed * CGFloat.random(in: 0.6...1.1)
            particles.append(Particle(position: point, velocity: CGPoint(-cos(angle) * v, sin(angle) * v),
                                      gravity: -220, life: life * CGFloat.random(in: 0.7...1), total: life,
                                      color: colors[i % colors.count], size: CGFloat.random(in: size), drift: drift,
                                      shape: shape))
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
        var shape: Shape = .dot

        enum Shape { case dot, heart, coin, spark }
    }

    private struct Popup {
        let text: String
        var position: CGPoint
        var life: CGFloat
    }

    // MARK: 그리기

    func screenX(_ worldX: Double) -> CGFloat { Self.runnerX + CGFloat(worldX - game.distance) }

    /// 지금 러너 왼쪽 끝의 화면 x (←→로 움직인 만큼).
    private var runnerLeft: CGFloat { Self.runnerX + CGFloat(game.runnerOffset) }

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
        self.groundY = groundY

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

        if let ghost = ghost?.game {
            let left = Self.runnerX + CGFloat(ghost.distance + ghost.runnerOffset - game.distance)
            if left > -60, left < size.width + 20 {
                cg.saveGState()
                cg.setAlpha(0.38)
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                drawRunner(cg, ghost, character: ghostCharacter, left: left, groundY: groundY, stageAnchorX: stageAnchorX,
                           stageScale: stageScale, theme: ghostCharacter.theme(.natural), time: time)
                cg.endTransparencyLayer()
                cg.restoreGState()
            }
        }
        drawTrail(cg, groundY: groundY, time: time)
        // 보호막이 깨진 뒤 지나가는 동안은 깜빡인다
        let blink = game.invulnerable > 0 && Int(time * 18) % 2 == 0
        cg.saveGState()
        if blink { cg.setAlpha(0.35) }
        drawRunner(cg, game, character: character, left: runnerLeft, groundY: groundY, stageAnchorX: stageAnchorX, stageScale: stageScale,
                   theme: theme, time: time)
        cg.restoreGState()
        drawAbilities(cg, groundY: groundY, time: time)

        // 파티클
        for p in particles {
            let alpha = max(0, min(1, p.life / p.total))
            let r = p.size
            let center = CGPoint(p.position.x, ground(Double(p.position.y)))
            switch p.shape {
            case .dot:
                cg.setFillColor(p.color.withAlphaComponent(alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            case .heart:
                Self.fillHeart(cg, at: center, size: r * 2.2, color: p.color.withAlphaComponent(alpha))
            case .spark:
                SpriteEffects.sparkle(cg, at: center, radius: r * 1.6, color: p.color.withAlphaComponent(alpha))
            case .coin:
                if let image = GameSprite.coin.frame(at: time + Double(r)) {
                    cg.saveGState()
                    cg.setAlpha(alpha)
                    GameAssets.draw(image, in: CGRect(x: center.x - r * 2, y: center.y - r * 2, width: r * 4, height: r * 4), cg)
                    cg.restoreGState()
                }
            }
        }

        // 먹은 코인이 왼쪽 위 코인 수로 날아간다
        let target = CGPoint(30, 49)
        for flyer in coinFlyers {
            let t = min(1, flyer.t)
            let e = t * t
            let x = flyer.from.x + (target.x - flyer.from.x) * e
            let y = flyer.from.y + (target.y - flyer.from.y) * e - sin(t * .pi) * 18
            let size = 12 - 5 * t
            if let image = GameSprite.coin.frame(at: time) {
                GameAssets.draw(image, in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size), cg)
            }
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

    /// 러너 하나 (내 러너 또는 고스트). 무대에서 게임으로 넘어가는 움직임은 내 러너에만 준다.
    private func drawRunner(_ cg: CGContext, _ game: RunnerGame, character: RunnerCharacter, left: CGFloat, groundY: CGFloat,
                            stageAnchorX: CGFloat, stageScale: CGFloat, theme: SpriteTheme, time: Double) {
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
            // 보폭 70pt마다 한 걸음 주기. 앞으로 움직이면 발이 빨라지고 몸을 앞으로 기울인다
            frame = MotionFrame(pose: CharacterPose(activity: .run, phase: CGFloat((game.distance + game.runnerOffset) / 70),
                                                    speed: 1.25))
            if game.isDucking { frame.transform.squash = 0.6 }
            if game === self.game, landBounce > 0 { frame.transform.squash = min(frame.transform.squash, 1 - 0.22 * landBounce) }
            frame.transform.rotation = CGFloat(game.moveDirection) * 0.08
        case .over:
            frame = MotionFrame(pose: CharacterPose(activity: .sit, phase: CGFloat(time / 1.1), mouthOpen: true))
            frame.effects = [.dizzyStars(CGFloat(time.truncatingRemainder(dividingBy: 1)))]
        }

        let gameScale = scale(for: character)
        let e = game === self.game ? entrance : 1
        let scale = stageScale + (gameScale - stageScale) * e
        let center = stageAnchorX + (left + CGFloat(Self.runnerWidth) / 2 - stageAnchorX) * e
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
    private func scale(for character: RunnerCharacter) -> CGFloat {
        if let cached = scaleCache[character.key] { return cached }
        let bounds = CharacterScene(rig: character.rig, pose: CharacterPose(activity: .stand)).bounds
        let scale = bounds.isNull ? Self.characterHeight / FittedRig.targetHeight
            : min(Self.characterHeight / max(bounds.height, 1), Self.characterWidth / max(bounds.width, 1))
        scaleCache[character.key] = scale
        return scale
    }

    /// 패널 폭에 맞게 긴 닉네임은 자른다.
    static func shortName(_ name: String?) -> String {
        guard let name else { return "고스트" }
        return name.count > 6 ? name.prefix(6) + "…" : name
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
        // 100점마다 점수가 잠깐 커진다
        let digits = GameFont.pixel(18 * (1 + 0.3 * milestoneGlow * milestoneGlow))
        let small = GameFont.pixel(12)
        let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

        if game.phase != .ready {
            let glow = milestoneGlow > 0 && Int(milestoneGlow * 10) % 2 == 0
            labels.append(Label(text: Text(String(format: "%05d", game.score)).font(digits)
                                    .foregroundColor(glow ? gold : .white),
                                position: CGPoint(12, 10), anchor: .topLeading))
            // 끝난 화면은 패널이 최고 점수를 보여 주고, 왼쪽 위 글자는 패널 가장자리와 겹친다
            if game.phase == .playing {
                labels.append(Label(text: Text("최고 \(max(game.best, game.score))").font(small)
                                        .foregroundColor(.white.opacity(0.75)),
                                    position: CGPoint(12, 29), anchor: .topLeading))
            }
            if game.phase == .playing, !game.abilities.isEmpty {
                var parts: [String] = []
                if game.abilities.shields > 0 { parts.append("보호막 \(game.shieldsLeft)") }
                if game.abilities.airJumps > 0 { parts.append("이단 점프") }
                if game.abilities.magnet > 0 { parts.append("자석") }
                if game.abilities.glide { parts.append("글라이드") }
                labels.append(Label(text: Text(parts.joined(separator: " · ")).font(small)
                                        .foregroundColor(Color(nsColor: NSColor(hex: 0x8FD3FF)).opacity(0.9)),
                                    position: CGPoint(12, 57), anchor: .topLeading))
            }
            if game.phase == .playing, game.coinsTaken > 0 || boosted {
                let double = boosted ? "  ×2 Claude 작업 중" : ""
                labels.append(Label(text: Text("코인 \(game.coinsTaken)\(double)").font(small).foregroundColor(gold.opacity(0.9)),
                                    position: CGPoint(12, 43), anchor: .topLeading))
            }
        }
        for popup in popups {
            labels.append(Label(text: Text(popup.text).font(GameFont.pixel(12))
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
        if game.phase == .playing, let lead = raceLead, let raceTarget {
            let who = Self.shortName(raceTarget.name)
            let text = lead > 0 ? "\(who) 추월! +\(lead)" : "\(who) \(raceTarget.score) (-\(1 - lead))"
            labels.append(Label(text: Text(text).font(small).foregroundColor(lead > 0 ? gold : .white.opacity(0.85)),
                                position: CGPoint(size.width / 2, 12)))
        }
        if let overtaken, game.phase == .playing {
            labels.append(Label(text: Text("\(overtaken.name) 추월!").font(GameFont.pixel(18))
                                    .foregroundColor(gold.opacity(Double(min(1, overtaken.life * 2)))),
                                position: CGPoint(size.width / 2, 34)))
        }
        if let zoneBanner, game.phase == .playing {
            labels.append(Label(text: Text(zoneBanner.text).font(GameFont.pixel(18))
                                    .foregroundColor(.white.opacity(Double(min(1, zoneBanner.life * 2)))),
                                position: CGPoint(size.width / 2, 52)))
        }
        if let notice {
            labels.append(Label(text: Text(notice.text).font(GameFont.pixel(12))
                                    .foregroundColor(Color(nsColor: NSColor(hex: 0x8FD3FF)).opacity(Double(min(1, notice.life * 2)))),
                                position: CGPoint(size.width / 2, game.phase == .playing ? 70 : 14)))
        }
        if recordBanner > 0, game.phase == .playing {
            labels.append(Label(text: Text("신기록!").font(GameFont.pixel(18))
                                    .foregroundColor(gold.opacity(Double(min(1, recordBanner * 3)))),
                                position: CGPoint(size.width / 2, overtaken == nil ? 34 : 52)))
        }

        let center = CGPoint(size.width / 2, size.height / 2 - 12)
        // 고스트 단축키. 겨룰 고스트 한 줄, 코드 복사·붙여넣기 한 줄
        var races: [String] = []
        if let savedGhost { races.append("G 내 고스트 \(savedGhost.score)") }
        if let top = TopGhost.all.record {
            races.append("1 \(top.rank.map { "\($0)위" } ?? "1위") \(Self.shortName(top.name))")
        }
        if let week = weekGhost {
            races.append("2 주간 \(Self.shortName(week.name))")
        }
        let ghostLines = races.isEmpty ? [] : [races.joined(separator: " · ")]
        let ghostColors = ghostLines.map { _ in gold.opacity(0.9) }
        let ghostExtra = CGFloat(ghostLines.count) * 14
        func addGhostLines(from y: CGFloat) {
            for (i, line) in ghostLines.enumerated() {
                labels.append(Label(text: Text(line).font(small).foregroundColor(ghostColors[i]),
                                    position: CGPoint(center.x, y + CGFloat(i) * 14)))
            }
        }
        switch game.phase {
        case .ready where entrance >= 1:
            panels.append(Panel(rect: CGRect(x: center.x - 125, y: center.y - 34, width: 250, height: 62 + ghostExtra)))
            labels.append(Label(text: Text("토큰 러너").font(GameFont.pixel(18))
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y - 18)))
            labels.append(Label(text: Text("스페이스·클릭으로 시작").font(GameFont.pixel(12))
                                    .foregroundColor(.white.opacity(0.9)), position: CGPoint(center.x, center.y)))
            let best = game.best > 0 ? "최고 \(game.best)  ·  " : ""
            labels.append(Label(text: Text("\(best)↑ 길게 높이 · ↓ 숙이기 · ←→ 이동").font(small)
                                    .foregroundColor(.white.opacity(0.65)), position: CGPoint(center.x, center.y + 16)))
            addGhostLines(from: center.y + 30)
        case .over:
            // 겨루는 판은 순위 대신 고스트와의 차이를 보여 준다
            let raceLine = raceLead.map { lead in
                lead > 0 ? "\(lead)점 앞섬 · 기록에는 남지 않음" : "\(-lead + 1)점 모자람"
            }
            let middle = raceLine ?? rankLine
            let won = (raceLead ?? 0) > 0
            let who = raceTarget?.name.map { "\(Self.shortName($0)) 고스트" } ?? "고스트"
            let title = isRace ? (won ? "\(who)를 이겼다!" : "\(who)에게 졌다")
                : game.isNewRecord ? "신기록!" : "앗, 부딪혔다"
            // 픽셀 글꼴은 줄 높이가 커서 줄 사이를 넉넉히 둔다
            labels.append(Label(text: Text(title).font(GameFont.pixel(18))
                                    .foregroundColor(won || (!isRace && game.isNewRecord) ? gold : .white),
                                position: CGPoint(center.x, center.y - 22)))
            labels.append(Label(text: Text("\(game.score)점").font(GameFont.pixel(24))
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y + 3)))
            var y = center.y + 25
            if let middle {
                labels.append(Label(text: Text(middle).font(small).foregroundColor(gold), position: CGPoint(center.x, y)))
                y += 14
            }
            labels.append(Label(text: Text("최고 \(game.best) · 스페이스로 새 판").font(small)
                                    .foregroundColor(.white.opacity(0.7)), position: CGPoint(center.x, y)))
            addGhostLines(from: y + 14)
            let bottom = y + ghostExtra + 10
            panels.append(Panel(rect: CGRect(x: center.x - 125, y: center.y - 36, width: 250, height: bottom - (center.y - 36))))
        default:
            break
        }
        return (panels, labels)
    }
}

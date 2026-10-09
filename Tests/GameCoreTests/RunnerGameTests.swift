import Testing
@testable import GameCore

/// 앱(GameAssets.catalog)과 같은 장애물 목록. 크기는 Assets/Game 스프라이트의 그림 영역을 2배로 잰 값이다.
private func catalog() -> [RunnerGame.ObstacleKind] {
    [
        .init(id: "spikes", width: 36, height: 18, groupSpeed: 300),
        .init(id: "mushroom", width: 24, height: 24),
        .init(id: "cactus", width: 28, height: 36, groupSpeed: 420),
        .init(id: "tree", width: 24, height: 36, minSpeed: 300, minGap: 130),
        .init(id: "crab", width: 30, height: 28, minSpeed: 260, minGap: 140, approachSpeed: 40),
        .init(id: "drill", width: 32, height: 38, minSpeed: 380, minGap: 160, approachSpeed: 70),
        .init(id: "bat", width: 48, height: 34, elevations: [22, 50], minSpeed: 330, minGap: 150),
    ]
}

/// 앱의 판정 상자 (GameSession.runnerWidth, runnerHeight).
private let runnerSize = (width: 24.0, height: 40.0)

private func makeGame(seed: UInt64 = 7, best: Int = 0, catalog: [RunnerGame.ObstacleKind] = catalog()) -> RunnerGame {
    var tuning = RunnerGame.Tuning()
    tuning.catalog = catalog
    return RunnerGame(tuning: tuning, runnerWidth: runnerSize.width, runnerHeight: runnerSize.height, best: best,
                      seed: seed)
}

private func autoplay(_ game: RunnerGame, seconds: Double) {
    let pilot = Autopilot(game: game)
    for _ in 0..<Int(seconds * 60) where game.phase == .playing {
        pilot.step()
        game.advance(by: 1.0 / 60)
    }
}

/// 판정 없이 굴리며 러너 앞끝이 장애물 앞끝에 닿는 시각을 잰다. 걸어오는 적도 실제로 만나는 때로 잰다.
private func meetings(seed: UInt64, seconds: Double) -> [(time: Double, obstacle: RunnerGame.Obstacle)] {
    let game = makeGame(seed: seed)
    game.ignoresCollisions = true
    game.press()
    game.release()
    var met: [Int: (Double, RunnerGame.Obstacle)] = [:]
    for _ in 0..<Int(seconds * 120) {
        game.advance(by: 1.0 / 120)
        for o in game.obstacles where met[o.id] == nil && o.x <= game.runnerBox.maxX {
            met[o.id] = (game.elapsed, o)
        }
    }
    return met.values.sorted { $0.0 < $1.0 }.map { (time: $0.0, obstacle: $0.1) }
}

@Suite struct RunnerGameTests {
    @Test func startsOnFirstPressAndJumps() {
        let game = makeGame()
        #expect(game.phase == .ready)
        game.press()
        #expect(game.phase == .playing)
        game.advance(by: 0.05)
        #expect(game.runnerY > 0)
        #expect(game.drainEvents().contains(.jumped))
    }

    @Test func fullJumpReachesExpectedApexAndLands() {
        let game = makeGame()
        game.press()   // 계속 누르고 있다
        var apex = 0.0
        for _ in 0..<120 {
            game.advance(by: 1.0 / 120)
            apex = max(apex, game.runnerY)
        }
        let expected = game.tuning.jumpVelocity * game.tuning.jumpVelocity / (2 * game.tuning.gravity)
        #expect(abs(apex - expected) < 3)
        #expect(game.isOnGround)
    }

    @Test func shortTapJumpsLower() {
        func apex(holding: Bool) -> Double {
            let game = makeGame()
            game.press()
            game.advance(by: 1.0 / 60)
            if !holding { game.release() }
            var top = 0.0
            for _ in 0..<60 {
                game.advance(by: 1.0 / 60)
                top = max(top, game.runnerY)
            }
            return top
        }
        #expect(apex(holding: false) < apex(holding: true) * 0.8)
    }

    @Test func jumpPressedJustBeforeLandingIsKept() {
        let game = makeGame()
        game.press()
        game.release()
        game.advance(by: 0.05)   // 떠오른 뒤
        // 내려오다 바닥 가까이에서 누른다 (jumpBuffer 안)
        while !(game.velocityY < 0 && game.runnerY < 12) { game.advance(by: 1.0 / 120) }
        game.press()
        _ = game.drainEvents()
        for _ in 0..<20 { game.advance(by: 1.0 / 120) }
        let events = game.drainEvents()
        #expect(events.contains(.landed))
        #expect(events.contains(.jumped))
    }

    @Test func standingStillCrashesAndKeepsBest() {
        let game = makeGame(best: 3)
        game.press()
        game.release()
        for _ in 0..<1_200 where game.phase == .playing { game.advance(by: 0.05) }
        #expect(game.phase == .over)
        #expect(game.crashedInto != nil)
        #expect(game.best >= 3)
        #expect(game.drainEvents().contains(.crashed))
    }

    @Test func restartWaitsBriefly() {
        let game = makeGame()
        game.press()
        for _ in 0..<1_000 where game.phase == .playing { game.advance(by: 0.1) }
        game.press()
        #expect(game.phase == .over)
        game.advance(by: game.tuning.restartDelay + 0.01)
        game.press()
        #expect(game.phase == .playing)
        #expect(game.score == 0)
        #expect(game.distance == 0)
    }

    @Test func speedRampsUpToMax() {
        let game = makeGame(catalog: [])   // 장애물 없이
        game.press()
        game.advance(by: 0.2)
        let early = game.speed
        for _ in 0..<2_000 { game.advance(by: 0.25) }
        #expect(early < game.speed)
        #expect(game.speed == game.tuning.maxSpeed)
    }

    @Test func scoreGrowsWithDistanceAndCoins() {
        let game = makeGame(catalog: [])
        game.press()
        game.advance(by: 0.25)
        game.advance(by: 0.25)
        #expect(game.score == Int(game.distance * game.tuning.scorePerPoint))
    }

    @Test func sameSeedSamePattern() {
        let a = makeGame(seed: 42), b = makeGame(seed: 42)
        a.press(); b.press()
        a.advance(by: 0.2); b.advance(by: 0.2)
        #expect(a.obstacles.map(\.x) == b.obstacles.map(\.x))
        #expect(a.obstacles.map(\.kind.id) == b.obstacles.map(\.kind.id))
    }

    /// 어떤 씨앗이든 만든 장애물은 뛰어넘거나 아래로 지나갈 수 있다.
    @Test(arguments: Array(UInt64(1)...UInt64(40)))
    func everyObstacleIsPassable(seed: UInt64) {
        let game = makeGame(seed: seed)
        let met = meetings(seed: seed, seconds: 60)
        #expect(met.count > 40)
        #expect(Set(met.map(\.obstacle.kind.id)).count == catalog().count)
        for (_, o) in met {
            let closing = o.spawnSpeed + o.kind.approachSpeed
            let under = o.y + game.tuning.hitInset >= runnerSize.height + 2
            let over = game.canJump(width: o.width, top: o.y + o.height, closingSpeed: closing)
            #expect(under || over, "seed \(seed) \(o.kind.id) ×\(o.count) at y \(o.y) closing \(closing)")
        }
    }

    /// 걸어오는 적까지 포함해, 앞 장애물을 만난 뒤 다음 장애물을 만나기까지 한 번 뛰고 다시 뛸 시간이 있다.
    @Test(arguments: Array(UInt64(1)...UInt64(40)))
    func everyGapLeavesTimeToLandAndJumpAgain(seed: UInt64) {
        let tuning = RunnerGame.Tuning()
        let met = meetings(seed: seed, seconds: 60)
        for (a, b) in zip(met, met.dropFirst()) {
            let between = b.time - a.time
            #expect(between >= tuning.airTime + tuning.reactionTime - 0.03,
                    "seed \(seed) \(a.obstacle.kind.id) → \(b.obstacle.kind.id): \(between)s")
        }
    }

    @Test func sameKindNeverMoreThanTwiceInARow() {
        let game = makeGame(seed: 9)
        game.ignoresCollisions = true
        game.press()
        var order: [Int: String] = [:]
        for _ in 0..<3_000 {
            for o in game.obstacles { order[o.id] = o.kind.id }
            game.advance(by: 1.0 / 30)
        }
        let kinds = order.sorted { $0.key < $1.key }.map(\.value)
        for i in 2..<max(kinds.count, 2) where kinds.count > 2 {
            #expect(!(kinds[i] == kinds[i - 1] && kinds[i] == kinds[i - 2]))
        }
    }

    @Test(arguments: [UInt64(3), 11, 29])
    func autoplayerSurvivesLongWhenJumpingAtTheRightTime(seed: UInt64) {
        let game = makeGame(seed: seed)
        game.press()
        game.release()
        autoplay(game, seconds: 40)
        let hit = game.obstacles.first { $0.id == game.crashedInto }
        #expect(game.elapsed > 20, "crashed at \(game.elapsed)s speed \(game.speed) into \(hit.map { "\($0.kind.id)×\($0.count) y\($0.y)" } ?? "-") runnerY \(game.runnerY)")
    }

    @Test func duckingPassesLowFlyer() {
        let bat = RunnerGame.ObstacleKind(id: "bat", width: 36, height: 20, elevations: [26], minGap: 150)
        let game = makeGame(seed: 1, catalog: [bat])
        game.press()
        game.release()
        game.setDuck(true)
        var passed = Set<Int>()
        for _ in 0..<400 where game.phase == .playing {
            game.advance(by: 1.0 / 30)
            for o in game.obstacles where o.x + o.width < game.runnerBox.minX { passed.insert(o.id) }
        }
        #expect(game.phase == .playing)
        #expect(passed.count >= 3)
    }

    @Test func newRecordAnnouncedOnceWhenPassingBest() {
        let game = makeGame(best: 5, catalog: [])
        game.press()
        var records = 0
        for _ in 0..<40 {
            game.advance(by: 0.25)
            records += game.drainEvents().filter { $0 == .newRecord }.count
        }
        #expect(records == 1)
        #expect(game.isNewRecord)
    }

    @Test func milestoneEveryHundred() {
        let game = makeGame(catalog: [])
        game.press()
        var milestones: [Int] = []
        for _ in 0..<200 {
            game.advance(by: 0.25)
            for case .milestone(let m) in game.drainEvents() { milestones.append(m) }
        }
        #expect(milestones.prefix(3) == [100, 200, 300])
    }
}

@Suite struct RunnerGameJumpTests {
    @Test func evenATinyTapClearsMinimumHeight() {
        var tuning = RunnerGame.Tuning()
        tuning.catalog = []
        let game = RunnerGame(tuning: tuning, runnerWidth: runnerSize.width, runnerHeight: runnerSize.height, seed: 1)
        game.press()
        game.release()   // 한 프레임도 안 누름
        var apex = 0.0
        for _ in 0..<120 {
            game.advance(by: 1.0 / 120)
            apex = max(apex, game.runnerY)
        }
        #expect(apex >= tuning.minJumpHeight)
        #expect(apex < tuning.jumpVelocity * tuning.jumpVelocity / (2 * tuning.gravity) * 0.85)
    }
}

@Suite struct RunnerGameCrashTests {
    @Test func crashingInTheAirFallsToTheGround() {
        let bat = RunnerGame.ObstacleKind(id: "bat", width: 36, height: 20, elevations: [60], minGap: 150)
        var tuning = RunnerGame.Tuning()
        tuning.catalog = [bat]
        let game = RunnerGame(tuning: tuning, runnerWidth: runnerSize.width, runnerHeight: runnerSize.height, seed: 2)
        game.press()   // 계속 누른 채 뛰어 높은 박쥐에 부딪힌다
        for _ in 0..<2_000 where game.phase == .playing {
            if game.isOnGround {
                game.release()
                game.press()
            }
            game.advance(by: 1.0 / 60)
        }
        #expect(game.phase == .over)
        let crashedAt = game.runnerY
        game.advance(by: 1)
        #expect(crashedAt > 0)
        #expect(game.runnerY == 0)
        #expect(game.isOnGround)
    }
}

@Suite struct RunnerGameDuckTests {
    @Test func jumpingWhileHoldingDuckStillReachesMinimumHeight() {
        let game = makeGame(catalog: [])
        game.press()
        game.release()
        game.advance(by: 0.3)   // 첫 점프가 끝나게
        game.setDuck(true)
        game.press()
        var apex = 0.0
        for _ in 0..<120 {
            game.advance(by: 1.0 / 120)
            apex = max(apex, game.runnerY)
        }
        #expect(apex >= game.tuning.minJumpHeight)
    }
}

@Suite struct RunnerGameMoveTests {
    @Test func movesWithinRange() {
        let game = makeGame(catalog: [])
        game.press()
        game.release()
        game.setMove(forward: true)
        game.advance(by: 0.25)
        #expect(game.runnerOffset > 0)
        game.advance(by: 0.25)
        game.advance(by: 0.25)
        game.advance(by: 0.25)
        #expect(game.runnerOffset == game.tuning.maxAdvance)
        game.setMove(back: true)
        game.advance(by: 0.25)
        #expect(game.runnerOffset == game.tuning.maxAdvance)   // 둘 다 누르면 서 있는다
        game.setMove(forward: false)
        for _ in 0..<8 { game.advance(by: 0.25) }
        #expect(game.runnerOffset == -game.tuning.maxRetreat)
    }

    @Test func doesNotMoveBeforeStart() {
        let game = makeGame(catalog: [])
        game.setMove(forward: true)
        game.advance(by: 1)
        #expect(game.runnerOffset == 0)
    }

    @Test func movingShiftsHitBoxButNotScore() {
        let still = makeGame(seed: 3)
        let moving = makeGame(seed: 3)
        for game in [still, moving] {
            game.ignoresCollisions = true
            game.press()
            game.release()
        }
        moving.setMove(forward: true)
        for _ in 0..<600 {
            still.advance(by: 1.0 / 120)
            moving.advance(by: 1.0 / 120)
        }
        #expect(moving.runnerBox.minX - still.runnerBox.minX == moving.runnerOffset)
        #expect(moving.runnerOffset == moving.tuning.maxAdvance)
        // 코인을 더 먹었을 수 있으니 거리 점수만 비교한다
        let distanceScore = { (g: RunnerGame) in g.score - g.coinsTaken * g.tuning.coinValue }
        #expect(distanceScore(moving) == distanceScore(still))
    }

    @Test func restartReturnsHomeAndReleasesKeys() {
        let game = makeGame()
        game.press()
        game.release()
        game.setMove(forward: true)
        for _ in 0..<(60 * 60) where game.phase == .playing { game.advance(by: 1.0 / 60) }
        #expect(game.phase == .over)
        #expect(game.runnerOffset > 0)
        game.advance(by: 1)
        game.press()
        #expect(game.phase == .playing)
        #expect(game.runnerOffset == 0)
        #expect(game.moveDirection == 0)
    }
}

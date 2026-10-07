import Foundation

/// 팝오버 무대에서 하는 장애물 피하기 게임의 규칙. 화면·입력·소리와 떨어진 순수 시뮬레이션이라
/// 같은 씨앗이면 같은 판이 나온다.
///
/// 장애물 간격과 종류를 늘려 가는 방식은 Chromium T-Rex Runner(components/neterror/resources/offline.js,
/// Copyright 2014 The Chromium Authors, BSD 3-Clause)를 따랐다. 간격은 장애물 폭 × 속도 + 종류별 최소 간격 × 계수이고
/// 1.5배까지 무작위로 늘린다. 같은 종류는 두 번까지만 잇달아 나오고, 여러 개 붙은 장애물과 나는 장애물은 일정 속도부터 나온다.
/// 여기에 점프 시간으로 잰 하한을 더해, 넘을 수 없는 배치는 만들지 않는다.
///
/// 좌표: x는 앞으로(+), y는 바닥에서 위로(+), 단위 pt. 1/120초 고정 간격으로 진행해 화면 주사율과 상관없이 같다.
public final class RunnerGame {
    public enum Phase: Equatable {
        case ready, playing, over
    }

    /// 화면이 소리·파티클로 받는 일.
    public enum Event: Equatable {
        case started
        case jumped
        case landed
        case coin(id: Int)
        /// 100점마다.
        case milestone(Int)
        /// 이번 판에서 처음으로 지난 최고 점수를 넘었을 때 한 번.
        case newRecord
        case crashed
    }

    public struct ObstacleKind: Equatable {
        public let id: String
        public let width: Double
        public let height: Double
        /// 바닥에서 띄운 높이 후보. 비어 있으면 땅 위에 놓인다.
        public let elevations: [Double]
        /// 이 속도(pt/초)부터 나온다.
        public let minSpeed: Double
        /// 이 속도부터 2~3개를 붙여 낸다. nil이면 늘 하나.
        public let groupSpeed: Double?
        /// 종류별 최소 간격(pt). T-Rex Runner의 minGap처럼 계수를 곱해 쓴다.
        public let minGap: Double
        /// 땅보다 빠르게 다가오는 속도(pt/초). 걸어오는 적.
        public let approachSpeed: Double

        public init(id: String, width: Double, height: Double, elevations: [Double] = [], minSpeed: Double = 0,
                    groupSpeed: Double? = nil, minGap: Double = 120, approachSpeed: Double = 0) {
            self.id = id
            self.width = width
            self.height = height
            self.elevations = elevations
            self.minSpeed = minSpeed
            self.groupSpeed = groupSpeed
            self.minGap = minGap
            self.approachSpeed = approachSpeed
        }
    }

    public struct Obstacle: Equatable, Identifiable {
        public let id: Int
        public let kind: ObstacleKind
        /// 왼쪽 끝 (세계 x).
        public internal(set) var x: Double
        /// 아래끝 높이.
        public let y: Double
        /// 붙여 낸 개수.
        public let count: Int
        /// 만들 때의 땅 속도. 속도는 줄지 않으니 이보다 느릴 때 만나는 일은 없다.
        public let spawnSpeed: Double

        public var width: Double { kind.width * Double(count) }
        public var height: Double { kind.height }
    }

    public struct Coin: Equatable, Identifiable {
        public let id: Int
        /// 가운데 (세계 x, 바닥 위 높이).
        public let x: Double
        public let y: Double
        public internal(set) var taken = false
    }

    public struct Tuning {
        public var gravity: Double = 2400
        public var jumpVelocity: Double = 560
        /// 점프 키를 일찍 떼면 오르는 속도를 여기까지 줄인다. 짧게 누르면 낮게 뛴다.
        public var releaseVelocity: Double = 280
        /// 아무리 짧게 눌러도 여기까지는 오른 뒤에 끊는다 (T-Rex Runner의 MIN_JUMP_HEIGHT).
        public var minJumpHeight: Double = 30
        /// 공중에서 숙이기를 누르면 빨리 내려온다.
        public var fastFallGravity: Double = 6200
        public var startSpeed: Double = 220
        /// 무대 폭(약 290pt 앞까지 보임)에서 장애물을 보고 반응할 시간이 0.6초는 남게 둔다.
        public var maxSpeed: Double = 440
        /// 초당 늘어나는 속도.
        public var acceleration: Double = 6
        /// 땅을 막 떠난 뒤에도 점프를 받아 주는 시간, 착지 직전에 누른 점프를 기억해 두는 시간.
        public var coyoteTime: Double = 0.08
        public var jumpBuffer: Double = 0.12
        /// T-Rex Runner의 GAP_COEFFICIENT, MAX_GAP_COEFFICIENT, MAX_OBSTACLE_DUPLICATION.
        public var gapCoefficient: Double = 0.6
        public var maxGapCoefficient: Double = 1.5
        public var maxDuplication = 2
        /// 착지한 뒤 다시 뛰기까지 사람에게 주는 시간.
        public var reactionTime: Double = 0.28
        /// 숙인 키 (선 키 대비).
        public var duckRatio: Double = 0.55
        /// 판정은 보이는 모습보다 조금 너그럽게 한다.
        public var hitInset: Double = 2.5
        /// 1pt당 점수와 코인 하나의 점수.
        public var scorePerPoint: Double = 0.04
        public var coinValue = 10
        /// 장애물·코인을 미리 깔아 두는 거리 (보이는 폭보다 넉넉히).
        public var lookAhead: Double = 520
        /// 부딪힌 뒤 다시 시작을 받기까지. 누르던 손에 바로 새 판이 시작되지 않게.
        public var restartDelay: Double = 0.45
        public var catalog: [ObstacleKind] = []

        public init() {}

        /// 점프 한 번에 공중에 머무는 시간.
        public var airTime: Double { 2 * jumpVelocity / gravity }
    }

    public let tuning: Tuning
    /// 러너 판정 상자 (선 자세).
    public let runnerWidth: Double
    public let runnerHeight: Double

    public private(set) var phase: Phase = .ready
    public private(set) var distance: Double = 0
    public private(set) var speed: Double
    /// 판이 시작된 뒤 흐른 시간. 부딪히면 멈춘다.
    public private(set) var elapsed: Double = 0
    public private(set) var runnerY: Double = 0
    public private(set) var velocityY: Double = 0
    public private(set) var isOnGround = true
    public private(set) var obstacles: [Obstacle] = []
    public private(set) var coins: [Coin] = []
    public private(set) var coinsTaken = 0
    public private(set) var score = 0
    public private(set) var best: Int
    /// 판이 시작할 때의 최고 점수. 신기록인지 가른다.
    public private(set) var bestAtStart: Int
    public private(set) var crashedInto: Int?
    public var isNewRecord: Bool { score > bestAtStart && bestAtStart > 0 }

    /// 숙이기를 누르고 있고 땅에 있으면 숙인다.
    public var isDucking: Bool { duckHeld && isOnGround }

    private var random: SplitMix64
    private var events: [Event] = []
    private var accumulator: Double = 0
    private var crashTime: Double = 0
    private var overClock: Double = 0
    private var jumpHeld = false
    /// 최소 높이에 닿기 전에 뗀 점프. 닿는 순간 끊는다.
    private var cutPending = false
    private var duckHeld = false
    private var coyote: Double = 0
    private var buffered: Double = 0
    private var nextSpawnX: Double = 0
    /// 다음에 놓을 종류. 간격을 정할 때 그 장애물이 걸어오는지 알아야 해서 미리 고른다.
    private var upcoming: ObstacleKind?
    private var recentKinds: [String] = []
    private var lastMilestone = 0
    private var announcedRecord = false
    private var nextID = 0
    /// 판정 없이 배치만 길게 볼 때 (테스트).
    var ignoresCollisions = false

    public static let step: Double = 1.0 / 120

    public init(tuning: Tuning, runnerWidth: Double, runnerHeight: Double, best: Int = 0,
                seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.tuning = tuning
        self.runnerWidth = runnerWidth
        self.runnerHeight = runnerHeight
        self.best = best
        bestAtStart = best
        speed = tuning.startSpeed
        random = SplitMix64(seed: seed)
        nextSpawnX = Self.firstSpawn(tuning)
    }

    /// 처음 장애물은 시작하고 2초쯤 뒤에 닿게 둔다.
    private static func firstSpawn(_ tuning: Tuning) -> Double { tuning.startSpeed * 2 }

    // MARK: 입력

    /// 점프 키를 눌렀다. 대기 중이면 시작하며 뛰고, 끝났으면 잠깐 뒤부터 새 판을 연다.
    public func press() {
        switch phase {
        case .ready:
            start()
            jumpHeld = true
            buffered = tuning.jumpBuffer
        case .playing:
            jumpHeld = true
            buffered = tuning.jumpBuffer
        case .over:
            guard overClock >= tuning.restartDelay else { return }
            reset()
            start()
        }
    }

    /// 점프 키를 뗐다. 오르는 중이면 짧게 끊는다.
    public func release() {
        jumpHeld = false
        cutPending = !isOnGround || buffered > 0
        cutJumpIfHighEnough()
    }

    private func cutJumpIfHighEnough() {
        guard cutPending, !isOnGround, runnerY >= tuning.minJumpHeight else { return }
        cutPending = false
        if velocityY > tuning.releaseVelocity { velocityY = tuning.releaseVelocity }
    }

    public func setDuck(_ held: Bool) {
        duckHeld = held
        if held { buffered = 0 }
    }

    /// 쌓인 일을 꺼내 간다 (그린 뒤 소리·파티클로).
    public func drainEvents() -> [Event] {
        defer { events.removeAll() }
        return events
    }

    // MARK: 진행

    /// 화면 한 장면만큼 시간을 보낸다. 오래 멈췄다 와도 한 번에 0.25초까지만 따라잡는다.
    public func advance(by seconds: Double) {
        if phase == .over {
            overClock += max(0, seconds)
            fallAfterCrash(min(max(0, seconds), 0.25))
        }
        guard phase == .playing else { return }
        accumulator += min(max(0, seconds), 0.25)
        while accumulator >= Self.step, phase == .playing {
            tick(Self.step)
            accumulator -= Self.step
        }
    }

    private func start() {
        phase = .playing
        events.append(.started)
    }

    private func reset() {
        phase = .ready
        distance = 0
        speed = tuning.startSpeed
        elapsed = 0
        runnerY = 0
        velocityY = 0
        isOnGround = true
        obstacles = []
        coins = []
        coinsTaken = 0
        score = 0
        bestAtStart = best
        crashedInto = nil
        accumulator = 0
        overClock = 0
        jumpHeld = false
        cutPending = false
        coyote = 0
        buffered = 0
        nextSpawnX = Self.firstSpawn(tuning)
        upcoming = nil
        recentKinds = []
        lastMilestone = 0
        announcedRecord = false
    }

    private func tick(_ dt: Double) {
        elapsed += dt
        speed = min(tuning.maxSpeed, speed + tuning.acceleration * dt)
        distance += speed * dt
        for i in obstacles.indices where obstacles[i].kind.approachSpeed > 0 {
            obstacles[i].x -= obstacles[i].kind.approachSpeed * dt
        }

        // 점프: 착지 직전에 누른 것도, 땅을 막 떠난 뒤에 누른 것도 받아 준다
        coyote = isOnGround ? tuning.coyoteTime : coyote - dt
        buffered -= dt
        if buffered > 0, coyote > 0 {
            velocityY = tuning.jumpVelocity
            cutPending = !jumpHeld
            isOnGround = false
            coyote = 0
            buffered = 0
            events.append(.jumped)
        }
        // 숙인 채 뛰어도 최소 높이까지는 오른 뒤에 빨리 내려온다
        let fastFall = duckHeld && !isOnGround && (velocityY <= 0 || runnerY >= tuning.minJumpHeight)
        let gravity = fastFall ? tuning.fastFallGravity : tuning.gravity
        velocityY -= gravity * dt
        runnerY += velocityY * dt
        if runnerY <= 0 {
            runnerY = 0
            velocityY = 0
            if !isOnGround { events.append(.landed) }
            isOnGround = true
            cutPending = false
        } else {
            isOnGround = false
            cutJumpIfHighEnough()
        }

        spawn()
        obstacles.removeAll { $0.x + $0.width < distance - 120 }
        coins.removeAll { $0.x < distance - 120 }

        collectCoins()
        if !ignoresCollisions, let hit = obstacles.first(where: hits) {
            crash(into: hit)
            return
        }
        updateScore()
    }

    /// 공중에서 부딪히면 그 자리에 떠 있지 않고 바닥으로 떨어진다 (판정 없이 모습만).
    private func fallAfterCrash(_ dt: Double) {
        guard runnerY > 0 else { return }
        velocityY = min(velocityY, 0) - tuning.gravity * dt
        runnerY = max(0, runnerY + velocityY * dt)
        if runnerY == 0 {
            velocityY = 0
            isOnGround = true
        }
    }

    private func crash(into obstacle: Obstacle) {
        crashedInto = obstacle.id
        phase = .over
        overClock = 0
        crashTime = elapsed
        updateScore()
        best = max(best, score)
        events.append(.crashed)
    }

    private func updateScore() {
        score = Int(distance * tuning.scorePerPoint) + coinsTaken * tuning.coinValue
        let milestone = score / 100
        if milestone > lastMilestone {
            lastMilestone = milestone
            events.append(.milestone(milestone * 100))
        }
        if !announcedRecord, bestAtStart > 0, score > bestAtStart {
            announcedRecord = true
            events.append(.newRecord)
        }
    }

    // MARK: 판정

    /// 러너 상자 (세계 좌표). 러너의 왼쪽 끝이 distance에 있다.
    public var runnerBox: Box {
        let height = isDucking ? runnerHeight * tuning.duckRatio : runnerHeight
        return Box(minX: distance + 2, maxX: distance + runnerWidth - 2, minY: runnerY, maxY: runnerY + height)
    }

    public struct Box: Equatable {
        public let minX, maxX, minY, maxY: Double

        func intersects(_ other: Box) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }
    }

    private func box(_ obstacle: Obstacle) -> Box {
        let inset = tuning.hitInset
        return Box(minX: obstacle.x + inset, maxX: obstacle.x + obstacle.width - inset,
                   minY: obstacle.y + (obstacle.y > 0 ? inset : 0), maxY: obstacle.y + obstacle.height - inset)
    }

    private func hits(_ obstacle: Obstacle) -> Bool { runnerBox.intersects(box(obstacle)) }

    private func collectCoins() {
        let runner = runnerBox
        let reach = 9.0   // 코인 반지름보다 조금 넉넉히
        for i in coins.indices where !coins[i].taken {
            let c = coins[i]
            if c.x + reach > runner.minX, c.x - reach < runner.maxX, c.y + reach > runner.minY, c.y - reach < runner.maxY {
                coins[i].taken = true
                coinsTaken += 1
                events.append(.coin(id: c.id))
            }
        }
    }

    // MARK: 장애물 만들기

    /// 높이 `top`까지 솟은 폭 `width` 장애물을 지금 속도로 뛰어넘을 수 있는지.
    /// 그 높이보다 위에 떠 있는 시간 동안 러너가 장애물과 자기 폭을 모두 지나가야 한다.
    public func canJump(width: Double, top: Double, closingSpeed: Double) -> Bool {
        let v = tuning.jumpVelocity, g = tuning.gravity
        let clearance = top - tuning.hitInset
        let disc = v * v - 2 * g * clearance
        guard disc > 0 else { return false }
        let window = 2 * disc.squareRoot() / g
        return window * closingSpeed >= width + runnerWidth - tuning.hitInset * 2 + 6
    }

    /// 서서 그 아래로 지나갈 수 있는지 (높이 떠 있는 장애물).
    private func canPassUnder(_ bottom: Double) -> Bool { bottom + tuning.hitInset >= runnerHeight + 2 }

    private func spawn() {
        while nextSpawnX < distance + tuning.lookAhead {
            guard let kind = upcoming ?? pickKind() else { return }
            let closing = speed + kind.approachSpeed
            let y = pickElevation(kind, closing: closing)
            var count = 1
            if let groupSpeed = kind.groupSpeed, speed >= groupSpeed {
                count = 1 + Int(random.next() % 3)
                while count > 1, !canJump(width: kind.width * Double(count), top: kind.height, closingSpeed: closing) {
                    count -= 1
                }
            }
            let obstacle = Obstacle(id: makeID(), kind: kind, x: nextSpawnX, y: y, count: count, spawnSpeed: speed)
            obstacles.append(obstacle)
            recentKinds.append(kind.id)
            if recentKinds.count > tuning.maxDuplication { recentKinds.removeFirst() }
            placeCoins(near: obstacle)
            upcoming = pickKind()
            nextSpawnX = obstacle.x + obstacle.width + gap(after: obstacle, next: upcoming)
        }
    }

    private func pickKind() -> ObstacleKind? {
        let open = tuning.catalog.filter { speed >= $0.minSpeed }
        // 같은 종류는 maxDuplication번까지만 잇달아
        let repeated = recentKinds.count == tuning.maxDuplication && Set(recentKinds).count == 1 ? recentKinds.first : nil
        let pool = open.filter { $0.id != repeated }
        let choices = pool.isEmpty ? open : pool
        guard !choices.isEmpty else { return nil }
        return choices[Int(random.next() % UInt64(choices.count))]
    }

    /// 떠 있는 장애물은 서서 지나가거나 뛰어넘을 수 있는 높이만 고른다. 숙이기는 키보드가 있어야 해서 필수로 두지 않는다.
    private func pickElevation(_ kind: ObstacleKind, closing: Double) -> Double {
        let fair = kind.elevations.filter {
            canPassUnder($0) || canJump(width: kind.width, top: $0 + kind.height, closingSpeed: closing)
        }
        guard !fair.isEmpty else { return kind.elevations.max() ?? 0 }
        return fair[Int(random.next() % UInt64(fair.count))]
    }

    /// T-Rex Runner의 간격 공식에, 착지하고 다시 뛸 시간을 하한으로 더한다.
    /// 다음 장애물이 걸어오는 적이면 만날 때까지 다가오는 거리만큼 더 띄운다. 보이기 시작할 때(lookAhead)부터
    /// 만날 때까지 걷는 거리가 가장 길어서 그 값으로 잡는다.
    private func gap(after obstacle: Obstacle, next: ObstacleKind?) -> Double {
        let chrome = obstacle.width * (speed / 60) + obstacle.kind.minGap * tuning.gapCoefficient
        let landing = speed * (tuning.airTime + tuning.reactionTime)
        let approach = next.map { $0.approachSpeed * tuning.lookAhead / (speed + $0.approachSpeed) } ?? 0
        let minGap = max(chrome, landing) + approach
        let maxGap = minGap * tuning.maxGapCoefficient
        return minGap + (maxGap - minGap) * random.unit()
    }

    /// 땅 장애물 위에 점프 궤적을 따라 코인 셋, 가끔은 다음 장애물 앞 바닥에 코인 줄.
    /// 걸어오는 적은 만날 때 자리가 달라져 궤적과 어긋나니 두지 않는다.
    private func placeCoins(near obstacle: Obstacle) {
        guard obstacle.y == 0, obstacle.kind.approachSpeed == 0 else { return }
        let roll = random.unit()
        if roll < 0.32 {
            let center = obstacle.x + obstacle.width / 2
            let top = obstacle.height + 20
            for (dx, lift) in [(-26.0, 0.72), (0, 1.0), (26, 0.72)] {
                coins.append(Coin(id: makeID(), x: center + dx, y: top * lift + 6))
            }
        } else if roll < 0.45 {
            let start = obstacle.x + obstacle.width + speed * (tuning.airTime * 0.9)
            for k in 0..<3 {
                coins.append(Coin(id: makeID(), x: start + Double(k) * 22, y: 12))
            }
        }
    }

    private func makeID() -> Int {
        nextID += 1
        return nextID
    }
}

/// 씨앗이 같으면 같은 수열을 내는 난수 (SplitMix64).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 이상 1 미만.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

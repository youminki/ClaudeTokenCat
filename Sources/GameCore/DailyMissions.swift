/// 날마다 바뀌는 미션 세 개, 또는 주마다 바뀌는 도전 세 개. 날짜(yyyymmdd)나 주(yyyyww)로 고르므로
/// 그 기간에는 누구에게나 같다. 판이 끝날 때마다 그 판의 기록을 더하고, 새로 채운 미션을 돌려준다
/// (보상은 앱이 지갑에 넣는다).
public struct DailyMissions: Codable, Equatable {
    public enum Period: String, Codable {
        case day, week
    }

    public enum Kind: String, Codable, CaseIterable {
        /// 하루 동안 먹은 코인
        case coins
        /// 하루 동안 아슬아슬하게 피한 수
        case nearMisses
        /// 한 판 점수
        case score
        /// 하루 동안 한 판 수
        case plays
        /// 하루 동안 뛴 수
        case jumps
        /// 고스트를 이긴 수
        case ghostWins
        /// 기간 동안 낸 점수의 합 (주간 도전만)
        case totalScore
    }

    public struct Mission: Codable, Equatable {
        public let kind: Kind
        public let target: Int
        public let reward: Int
    }

    /// 한 판의 기록.
    public struct Run {
        public var coins = 0
        public var nearMisses = 0
        public var score = 0
        public var jumps = 0
        public var wonRace = false

        public init(coins: Int = 0, nearMisses: Int = 0, score: Int = 0, jumps: Int = 0, wonRace: Bool = false) {
            self.coins = coins
            self.nearMisses = nearMisses
            self.score = score
            self.jumps = jumps
            self.wonRace = wonRace
        }
    }

    /// 날짜(yyyymmdd) 또는 주(yyyyww).
    public let day: Int
    public let missions: [Mission]
    public private(set) var progress: [Int]
    /// 옛 저장값에는 없어서 비어 있으면 하루 미션으로 읽는다.
    private let period: Period?

    public var isWeekly: Bool { period == .week }

    /// 종류별 (쉬운 목표, 어려운 목표, 쉬운 보상).
    private static let daily: [Kind: (easy: Int, hard: Int, reward: Int)] = [
        .coins: (30, 70, 20),
        .nearMisses: (3, 6, 30),
        .score: (300, 600, 30),
        .plays: (3, 6, 15),
        .jumps: (40, 100, 20),
        .ghostWins: (1, 2, 40),
    ]

    /// 한 주에 걸쳐 채우는 큰 목표. 하루 미션 여러 날 치 보상을 준다.
    private static let weekly: [Kind: (easy: Int, hard: Int, reward: Int)] = [
        .coins: (250, 500, 120),
        .nearMisses: (25, 50, 140),
        .score: (900, 1400, 160),
        .plays: (20, 40, 100),
        .jumps: (400, 800, 110),
        .ghostWins: (3, 6, 150),
        .totalScore: (6000, 12000, 140),
    ]

    private static let dailyKinds: [Kind] = [.coins, .nearMisses, .score, .plays, .jumps, .ghostWins]

    public init(day: Int) {
        self.init(day, period: .day)
    }

    public static func week(_ week: Int) -> DailyMissions {
        DailyMissions(week, period: .week)
    }

    private init(_ day: Int, period: Period) {
        self.day = day
        self.period = period
        let table = period == .week ? Self.weekly : Self.daily
        // 같은 숫자의 날과 주가 같은 미션을 고르지 않게 씨앗을 바꾼다
        var random = SplitMix64(seed: UInt64(day) &* 0x9E37_79B9 &+ (period == .week ? 0x5EED : 0))
        // 하루 미션은 주간 도전이 생기기 전 순서 그대로 골라, 같은 날이면 버전이 달라도 같은 미션이 나온다
        var kinds = period == .week ? Kind.allCases : Self.dailyKinds
        var picked: [Mission] = []
        while picked.count < 3 {
            let kind = kinds.remove(at: Int(random.next() % UInt64(kinds.count)))
            guard let row = table[kind] else { continue }
            let hard = random.next() % 3 == 0
            picked.append(Mission(kind: kind, target: hard ? row.hard : row.easy, reward: hard ? row.reward * 2 : row.reward))
        }
        missions = picked
        progress = Array(repeating: 0, count: picked.count)
    }

    public func isDone(_ index: Int) -> Bool { progress[index] >= missions[index].target }

    public var doneCount: Int { missions.indices.filter(isDone).count }

    /// 판 하나를 더한다. 이번에 처음 채운 미션을 돌려준다.
    public mutating func record(_ run: Run) -> [Mission] {
        var completed: [Mission] = []
        for (i, mission) in missions.enumerated() {
            let wasDone = isDone(i)
            switch mission.kind {
            case .coins: progress[i] += run.coins
            case .nearMisses: progress[i] += run.nearMisses
            case .score: progress[i] = max(progress[i], run.score)
            case .plays: progress[i] += 1
            case .jumps: progress[i] += run.jumps
            case .ghostWins: progress[i] += run.wonRace ? 1 : 0
            case .totalScore: progress[i] += run.score
            }
            if !wasDone, isDone(i) { completed.append(mission) }
        }
        return completed
    }
}

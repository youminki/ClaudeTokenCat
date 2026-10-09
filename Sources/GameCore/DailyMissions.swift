/// 날마다 바뀌는 미션 세 개. 날짜(yyyymmdd)로 고르므로 그날은 누구에게나 같다.
/// 판이 끝날 때마다 그 판의 기록을 더하고, 새로 채운 미션을 돌려준다 (보상은 앱이 지갑에 넣는다).
public struct DailyMissions: Codable, Equatable {
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

    public let day: Int
    public let missions: [Mission]
    public private(set) var progress: [Int]

    /// 종류별 (쉬운 목표, 어려운 목표, 쉬운 보상).
    private static let table: [Kind: (easy: Int, hard: Int, reward: Int)] = [
        .coins: (30, 70, 20),
        .nearMisses: (3, 6, 30),
        .score: (300, 600, 30),
        .plays: (3, 6, 15),
        .jumps: (40, 100, 20),
        .ghostWins: (1, 2, 40),
    ]

    public init(day: Int) {
        self.day = day
        var random = SplitMix64(seed: UInt64(day) &* 0x9E37_79B9)
        var kinds = Kind.allCases
        var picked: [Mission] = []
        while picked.count < 3 {
            let kind = kinds.remove(at: Int(random.next() % UInt64(kinds.count)))
            guard let row = Self.table[kind] else { continue }
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
            }
            if !wasDone, isDone(i) { completed.append(mission) }
        }
        return completed
    }
}

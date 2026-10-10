/// 오래 쌓아 가는 업적. 판마다 누적 기록을 더하고, 단계를 새로 넘으면 보상을 돌려준다.
/// 단계는 순서대로만 받고, 한 판에 여러 단계를 넘으면 모두 준다.
public struct Achievements: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case plays, coins, bestScore, jumps, nearMisses, ghostWins, missions
    }

    public struct Tier: Equatable {
        public let kind: Kind
        /// 0부터 센 단계.
        public let level: Int
        public let target: Int
        public let reward: Int
    }

    /// 종류별 단계 목표. 보상은 단계마다 같은 표를 쓴다.
    public static let targets: [Kind: [Int]] = [
        .plays: [10, 50, 200, 1000],
        .coins: [100, 500, 2000, 10000],
        .bestScore: [500, 1000, 2000, 3000],
        .jumps: [200, 1000, 5000, 20000],
        .nearMisses: [20, 100, 500, 2000],
        .ghostWins: [1, 10, 50, 200],
        .missions: [5, 30, 100, 300],
    ]
    /// 능력은 점수에 영향을 주어, 업적만으로 능력을 금방 다 사지 않게 보상을 작게 둔다 (모두 합쳐 5,670).
    public static let rewards = [30, 80, 200, 500]

    /// 종류별 누적 값 (최고 점수는 가장 높은 값). 저장값은 이름을 키로 둬서 모르는 종류가 있어도 나머지를 읽는다.
    private var totals: [String: Int] = [:]
    /// 종류별로 받은 단계 수.
    private var reached: [String: Int] = [:]

    public init() {}

    public func value(_ kind: Kind) -> Int { totals[kind.rawValue] ?? 0 }
    public func levels(_ kind: Kind) -> Int { reached[kind.rawValue] ?? 0 }
    public static func maxLevel(_ kind: Kind) -> Int { targets[kind]?.count ?? 0 }

    /// 다음에 받을 단계. 모두 받았으면 nil.
    public func next(_ kind: Kind) -> Tier? {
        let level = levels(kind)
        guard let targets = Self.targets[kind], level < targets.count else { return nil }
        return Tier(kind: kind, level: level, target: targets[level], reward: Self.rewards[min(level, Self.rewards.count - 1)])
    }

    /// 판 하나와 그 판에 채운 미션 수를 더한다. 새로 넘은 단계를 돌려준다.
    public mutating func record(_ run: DailyMissions.Run, missionsDone: Int = 0) -> [Tier] {
        func add(_ kind: Kind, _ amount: Int) { totals[kind.rawValue, default: 0] += amount }
        add(.plays, 1)
        add(.coins, run.coins)
        totals[Kind.bestScore.rawValue] = max(value(.bestScore), run.score)
        add(.jumps, run.jumps)
        add(.nearMisses, run.nearMisses)
        add(.ghostWins, run.wonRace ? 1 : 0)
        add(.missions, missionsDone)
        var reachedNow: [Tier] = []
        for kind in Kind.allCases {
            while let tier = next(kind), value(kind) >= tier.target {
                reached[kind.rawValue] = tier.level + 1
                reachedNow.append(tier)
            }
        }
        return reachedNow
    }
}

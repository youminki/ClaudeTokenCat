/// 러너 레벨. 판마다 경험치가 쌓이고, 레벨이 오르면 보상을 준다.
public struct RunnerLevel: Codable, Equatable {
    public private(set) var level = 1
    /// 지금 레벨에서 모은 경험치.
    public private(set) var xp = 0

    public init() {}

    /// 다음 레벨까지 필요한 경험치. 레벨이 오를수록 조금씩 늘어난다.
    public static func needed(at level: Int) -> Int { 100 + (level - 1) * 40 }

    public var needed: Int { Self.needed(at: level) }

    /// 판 하나의 경험치: 점수 10점에 1, 코인 하나에 2, 판마다 5.
    public static func xp(for run: DailyMissions.Run) -> Int { run.score / 10 + run.coins * 2 + 5 }

    /// 오른 레벨 보상 코인. 다섯 레벨마다 행운 상자도 준다.
    public static func reward(reaching level: Int) -> (coins: Int, box: Bool) { (40 + level * 10, level % 5 == 0) }

    /// 경험치를 더하고 새로 오른 레벨들을 돌려준다.
    public mutating func add(_ amount: Int) -> [Int] {
        xp += max(0, amount)
        var reached: [Int] = []
        while xp >= needed {
            xp -= needed
            level += 1
            reached.append(level)
        }
        return reached
    }
}

/// 날마다 한 판 이상 하면 이어지는 출석. 하루라도 빠지면 1일부터 다시 센다.
public struct Attendance: Codable, Equatable {
    /// 마지막으로 출석한 날 (yyyymmdd를 날짜 차이로 셀 수 있게 줄리안 일수로 둔다).
    public private(set) var lastDay: Int?
    public private(set) var streak = 0

    public init() {}

    /// 7일 주기 보상. 일곱째 날은 코인을 크게 주고 행운 상자도 준다.
    public static let rewards = [20, 30, 40, 60, 80, 100, 200]

    public static func reward(day streak: Int) -> (coins: Int, box: Bool) {
        let index = (max(streak, 1) - 1) % rewards.count
        return (rewards[index], index == rewards.count - 1)
    }

    /// `day`는 연속인지 셀 수 있는 날 번호 (1970년부터 지난 날 수 등). 오늘 처음이면 이어진 날 수를 돌려준다.
    public mutating func check(in day: Int) -> Int? {
        if let lastDay, day <= lastDay { return nil }
        streak = lastDay == day - 1 ? streak + 1 : 1
        lastDay = day
        return streak
    }

    /// 오늘이 `day`일 때 이어지고 있는 날 수 (어제까지 했으면 아직 끊기지 않았다).
    public func current(on day: Int) -> Int {
        guard let lastDay, lastDay >= day - 1 else { return 0 }
        return streak
    }
}

/// 물건 등급. 행운 상자에서 나올 확률과 칸 테두리 색을 정한다.
public enum Rarity: Int, Codable, CaseIterable, Comparable {
    case common, rare, epic, legendary

    /// 행운 상자 가중치 (백분율).
    public var weight: Int {
        switch self {
        case .common: 60
        case .rare: 28
        case .epic: 10
        case .legendary: 2
        }
    }

    public static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
}

public enum LuckyBox {
    /// 아직 없는 물건 가운데 등급 가중치로 하나를 고른다. 그 등급에 남은 물건이 없으면 남은 등급끼리 다시 나눈다.
    /// `roll`은 0..<1 난수.
    public static func pick<Item>(from candidates: [(item: Item, rarity: Rarity)], roll: Double, second: Double) -> Item? {
        let rarities = Rarity.allCases.filter { rarity in candidates.contains { $0.rarity == rarity } }
        let total = rarities.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var point = roll * Double(total)
        var chosen = rarities[0]
        for rarity in rarities {
            if point < Double(rarity.weight) { chosen = rarity; break }
            point -= Double(rarity.weight)
            chosen = rarity
        }
        let pool = candidates.filter { $0.rarity == chosen }
        return pool[min(Int(second * Double(pool.count)), pool.count - 1)].item
    }
}

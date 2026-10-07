/// 순위 요약을 받을 때마다 지난번과 견줘 말풍선으로 알릴 소식을 고른다. 처음 받은 요약은 기준으로만 둔다.
/// 사람은 서버가 주는 키로 가린다. 닉네임만 바뀐 것은 소식이 아니고, 닉네임이 같아도 키가 다르면 다른 사람이다.
public struct RankSnapshot: Codable, Equatable {
    /// 키가 없던 예전 저장값은 닉네임으로 대신 가린다.
    public var topKey: String?
    public var weekTopKey: String?
    public var topName: String?
    public var topScore: Int?
    public var topIsYou: Bool
    public var weekTopName: String?
    public var weekTopScore: Int?
    public var weekTopIsYou: Bool
    public var myRank: Int?

    public init(topKey: String? = nil, topName: String?, topScore: Int?, topIsYou: Bool, weekTopKey: String? = nil,
                weekTopName: String?, weekTopScore: Int?, weekTopIsYou: Bool, myRank: Int?) {
        self.topKey = topKey
        self.weekTopKey = weekTopKey
        self.topName = topName
        self.topScore = topScore
        self.topIsYou = topIsYou
        self.weekTopName = weekTopName
        self.weekTopScore = weekTopScore
        self.weekTopIsYou = weekTopIsYou
        self.myRank = myRank
    }
}

public enum RankNews: Equatable {
    /// 다른 사람이 전체 1위가 됐다.
    case newChampion(name: String, score: Int)
    /// 1위가 자기 기록을 더 올렸다.
    case championImproved(name: String, score: Int)
    case youAreChampion(score: Int)
    case newWeeklyChampion(name: String, score: Int)
    /// 누가 나를 앞질러 순위가 내려갔다.
    case overtaken(from: Int, to: Int)
}

public enum RankFeed {
    /// 둘 다 키가 있으면 키로, 아니면(키가 없던 예전 저장값) 닉네임으로 같은 사람인지 본다.
    static func same(_ keyA: String?, _ nameA: String?, _ keyB: String?, _ nameB: String?) -> Bool {
        if let keyA, let keyB { return keyA == keyB }
        return nameA == nameB
    }

    public static func news(from old: RankSnapshot?, to new: RankSnapshot) -> [RankNews] {
        guard let old else { return [] }
        var news: [RankNews] = []
        var championChanged = false
        let samePerson = same(new.topKey, new.topName, old.topKey, old.topName)
        if let name = new.topName, let score = new.topScore, score != old.topScore || !samePerson {
            if new.topIsYou {
                if !old.topIsYou { news.append(.youAreChampion(score: score)) }
            } else if samePerson {
                news.append(.championImproved(name: name, score: score))
            } else {
                news.append(.newChampion(name: name, score: score))
                championChanged = true
            }
        }
        // 전체 1위와 같은 사람이면 이미 알렸으니 이번 주 소식은 뺀다
        if let name = new.weekTopName, let score = new.weekTopScore, !new.weekTopIsYou,
           !same(new.weekTopKey, name, old.weekTopKey, old.weekTopName),
           !(same(new.weekTopKey, name, new.topKey, new.topName) && score == new.topScore) {
            news.append(.newWeeklyChampion(name: name, score: score))
        }
        // 1위에서 밀린 것은 새 1위 소식이 대신한다
        if let before = old.myRank, let now = new.myRank, now > before, !(championChanged && before == 1) {
            news.append(.overtaken(from: before, to: now))
        }
        return news
    }
}

/// 게임 중 앞에 있는 사람들. 점수가 넘을 때마다 추월로 알리고, 다음 목표를 알려 준다.
public struct Rival: Equatable {
    public let name: String
    public let score: Int

    public init(name: String, score: Int) {
        self.name = name
        self.score = score
    }
}

public struct RivalTracker {
    /// 아직 넘지 못한 사람, 낮은 점수부터.
    public private(set) var ahead: [Rival]

    public init(rivals: [Rival]) {
        ahead = rivals.filter { $0.score > 0 }.sorted { $0.score < $1.score }
    }

    public var next: Rival? { ahead.first }

    /// 지금 점수로 넘은 사람들 (낮은 점수부터).
    public mutating func update(score: Int) -> [Rival] {
        let passed = ahead.prefix { $0.score < score }
        ahead.removeFirst(passed.count)
        return Array(passed)
    }
}

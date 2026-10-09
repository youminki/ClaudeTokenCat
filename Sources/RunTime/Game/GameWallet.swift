import AppKit
import Combine
import GameCore

/// 미니게임 러너에 다는 꾸미기. 그림만 바뀌고 판정과 점수는 같다.
enum Cosmetic: String, CaseIterable, Identifiable {
    case sparkleTrail, cometTrail, rainbowTrail, fireTrail, noteTrail, heartTrail
    case heartDust, goldDust, starDust, rainbowDust
    case fireworksCrash, heartCrash, coinCrash

    enum Slot: CaseIterable {
        case trail, dust, crash

        var title: String {
            switch self {
            case .trail: "꼬리"
            case .dust: "발먼지"
            case .crash: "부딪힘"
            }
        }
    }

    var id: String { rawValue }

    var slot: Slot {
        switch self {
        case .sparkleTrail, .cometTrail, .rainbowTrail, .fireTrail, .noteTrail, .heartTrail: .trail
        case .heartDust, .goldDust, .starDust, .rainbowDust: .dust
        case .fireworksCrash, .heartCrash, .coinCrash: .crash
        }
    }

    var name: String {
        switch self {
        case .sparkleTrail: "반짝이"
        case .cometTrail: "혜성"
        case .rainbowTrail: "무지개"
        case .fireTrail: "불꽃"
        case .noteTrail: "음표"
        case .heartTrail: "하트"
        case .heartDust: "분홍"
        case .goldDust: "금빛"
        case .starDust: "하늘빛"
        case .rainbowDust: "무지개"
        case .fireworksCrash: "폭죽"
        case .heartCrash: "하트 펑"
        case .coinCrash: "코인 비"
        }
    }

    var price: Int {
        switch self {
        case .heartDust: 40
        case .starDust: 60
        case .goldDust: 90
        case .rainbowDust: 150
        case .sparkleTrail: 120
        case .heartTrail: 140
        case .noteTrail: 160
        case .cometTrail: 180
        case .fireTrail: 240
        case .rainbowTrail: 300
        case .heartCrash: 100
        case .fireworksCrash: 200
        case .coinCrash: 350
        }
    }

    /// 발먼지 색, 꼬리의 바탕색.
    var color: NSColor {
        switch self {
        case .sparkleTrail, .goldDust: NSColor(hex: 0xFFD45E)
        case .cometTrail, .starDust: NSColor(hex: 0x8FD3FF)
        case .rainbowTrail: NSColor(hex: 0xFF9E3D)
        case .heartDust, .heartTrail, .heartCrash: NSColor(hex: 0xFF8FB8)
        case .fireTrail: NSColor(hex: 0xFF7A2F)
        case .noteTrail: NSColor(hex: 0xB79CFF)
        case .rainbowDust: NSColor(hex: 0x5BD86B)
        case .fireworksCrash: NSColor(hex: 0xFFE14D)
        case .coinCrash: NSColor(hex: 0xFFD45E)
        }
    }
}

/// 게임 코인 지갑, 산 꾸미기, 오늘의 미션. 이 Mac에만 저장한다.
final class GameWallet: ObservableObject {
    static let shared = GameWallet()

    private enum Key {
        static let coins = "gameWalletCoins"
        static let owned = "gameCosmeticsOwned"
        static let equipped = "gameCosmeticsEquipped"
        static let missions = "gameDailyMissions"
        static let unlocked = "gameUnlocked"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var coins: Int { didSet { defaults.set(coins, forKey: Key.coins) } }
    @Published private(set) var owned: Set<Cosmetic> {
        didSet { defaults.set(owned.map(\.rawValue), forKey: Key.owned) }
    }
    @Published private(set) var equipped: Set<Cosmetic> {
        didSet { defaults.set(equipped.map(\.rawValue), forKey: Key.equipped) }
    }
    @Published private var stored: DailyMissions
    /// 산 러너("runner:tiger")와 색("theme:gold").
    @Published private(set) var unlocked: Set<String> {
        didSet { defaults.set(Array(unlocked), forKey: Key.unlocked) }
    }

    private init() {
        coins = defaults.integer(forKey: Key.coins)
        let names = { (key: String) in Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(Cosmetic.init)) }
        let owned = names(Key.owned)
        self.owned = owned
        equipped = names(Key.equipped).intersection(owned)
        unlocked = Set(defaults.stringArray(forKey: Key.unlocked) ?? [])
        stored = defaults.data(forKey: Key.missions).flatMap { try? JSONDecoder().decode(DailyMissions.self, from: $0) }
            ?? DailyMissions(day: Self.today())
    }

    static func today(_ date: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// 오늘의 미션. 날이 바뀌었으면 새 미션.
    var missions: DailyMissions {
        let day = Self.today()
        return stored.day == day ? stored : DailyMissions(day: day)
    }

    /// 화면 점검 도구가 저장하지 않고 꾸미기를 달아 볼 때.
    var preview: Set<Cosmetic>?

    func equipped(_ slot: Cosmetic.Slot) -> Cosmetic? { (preview ?? equipped).first { $0.slot == slot } }

    /// 판이 끝났다. 먹은 코인을 넣고, 새로 채운 미션의 보상을 더해 그 미션들을 돌려준다.
    func finishRun(_ run: DailyMissions.Run, bonusCoins: Int = 0) -> [DailyMissions.Mission] {
        var board = missions
        let completed = board.record(run)
        stored = board
        if let data = try? JSONEncoder().encode(board) { defaults.set(data, forKey: Key.missions) }
        coins += run.coins + bonusCoins + completed.reduce(0) { $0 + $1.reward }
        return completed
    }

    func owns(_ runner: Runner) -> Bool { runner.price == nil || unlocked.contains("runner:\(runner.rawValue)") }
    func owns(_ theme: SpriteTheme) -> Bool { theme.price == nil || unlocked.contains("theme:\(theme.rawValue)") }

    /// 상점 러너를 산다. 코인이 모자라거나 이미 있으면 false.
    @discardableResult
    func buy(_ runner: Runner) -> Bool { unlock("runner:\(runner.rawValue)", price: runner.price) }

    @discardableResult
    func buy(_ theme: SpriteTheme) -> Bool { unlock("theme:\(theme.rawValue)", price: theme.price) }

    private func unlock(_ key: String, price: Int?) -> Bool {
        guard let price, !unlocked.contains(key), coins >= price else { return false }
        coins -= price
        unlocked.insert(key)
        return true
    }

    /// 없으면 사서 달고, 있으면 달거나 뗀다. 코인이 모자라면 false.
    @discardableResult
    func choose(_ item: Cosmetic) -> Bool {
        if !owned.contains(item) {
            guard coins >= item.price else { return false }
            coins -= item.price
            owned.insert(item)
        }
        if equipped.contains(item) {
            equipped.remove(item)
        } else {
            equipped = equipped.filter { $0.slot != item.slot }.union([item])
        }
        return true
    }
}

extension DailyMissions.Mission {
    var title: String {
        switch kind {
        case .coins: "코인 \(target)개 먹기"
        case .nearMisses: "아슬! \(target)번"
        case .score: "한 판 \(target)점 넘기"
        case .plays: "\(target)판 하기"
        case .jumps: "\(target)번 뛰기"
        case .ghostWins: target == 1 ? "고스트 이기기" : "고스트 \(target)번 이기기"
        }
    }

    var icon: String {
        switch kind {
        case .coins: "dollarsign.circle.fill"
        case .nearMisses: "bolt.fill"
        case .score: "flag.checkered"
        case .plays: "gamecontroller.fill"
        case .jumps: "arrow.up.circle.fill"
        case .ghostWins: "person.2.fill"
        }
    }
}

extension SpriteTheme {
    /// 고를 수 있는 색: 기본 색과 산 색. 지금 고른 색은 늘 넣는다.
    static func owned(current: SpriteTheme) -> [SpriteTheme] {
        allCases.filter { GameWallet.shared.owns($0) || $0 == current }
    }
}

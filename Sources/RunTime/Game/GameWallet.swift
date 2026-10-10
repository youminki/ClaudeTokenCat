import AppKit
import Combine
import GameCore

/// 미니게임 러너에 다는 꾸미기. 그림만 바뀌고 판정과 점수는 같다.
enum Cosmetic: String, CaseIterable, Identifiable {
    case sparkleTrail, cometTrail, rainbowTrail, fireTrail, noteTrail, heartTrail, magicTrail, smokeTrail, sparkTrail
    case heartDust, goldDust, starDust, rainbowDust, cloudDust
    case fireworksCrash, heartCrash, coinCrash, magicCrash, flameCrash
    case greenBuddy, blueBuddy, pinkBuddy, yellowBuddy, beigeBuddy, boxBuddy, tinyBuddy

    enum Slot: CaseIterable {
        case buddy, trail, dust, crash

        var title: String {
            switch self {
            case .buddy: "동료"
            case .trail: "꼬리"
            case .dust: "발먼지"
            case .crash: "부딪힘"
            }
        }
    }

    var id: String { rawValue }

    var slot: Slot {
        switch self {
        case .sparkleTrail, .cometTrail, .rainbowTrail, .fireTrail, .noteTrail, .heartTrail, .magicTrail, .smokeTrail,
             .sparkTrail: .trail
        case .heartDust, .goldDust, .starDust, .rainbowDust, .cloudDust: .dust
        case .fireworksCrash, .heartCrash, .coinCrash, .magicCrash, .flameCrash: .crash
        case .greenBuddy, .blueBuddy, .pinkBuddy, .yellowBuddy, .beigeBuddy, .boxBuddy, .tinyBuddy: .buddy
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
        case .magicTrail: "마법 별"
        case .smokeTrail: "증기"
        case .sparkTrail: "번개"
        case .cloudDust: "구름"
        case .magicCrash: "마법진"
        case .flameCrash: "불기둥"
        case .greenBuddy: "초록이"
        case .blueBuddy: "파랑이"
        case .pinkBuddy: "외눈이"
        case .yellowBuddy: "노랑이"
        case .beigeBuddy: "우주인"
        case .boxBuddy: "상자"
        case .tinyBuddy: "꼬마"
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
        case .cloudDust: 120
        case .smokeTrail: 200
        case .magicTrail: 280
        case .sparkTrail: 380
        case .flameCrash: 260
        case .magicCrash: 400
        case .tinyBuddy: 220
        case .greenBuddy: 300
        case .blueBuddy: 300
        case .yellowBuddy: 340
        case .pinkBuddy: 380
        case .beigeBuddy: 450
        case .boxBuddy: 600
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
        case .magicTrail, .magicCrash: NSColor(hex: 0xC68CFF)
        case .smokeTrail, .cloudDust: NSColor(hex: 0xE8EEF5)
        case .sparkTrail: NSColor(hex: 0x7FE9FF)
        case .flameCrash: NSColor(hex: 0xFF8A3D)
        case .greenBuddy: NSColor(hex: 0x5BD86B)
        case .blueBuddy: NSColor(hex: 0x6FA8FF)
        case .pinkBuddy: NSColor(hex: 0xFF8FB8)
        case .yellowBuddy: NSColor(hex: 0xFFC94D)
        case .beigeBuddy: NSColor(hex: 0xE8C8A0)
        case .boxBuddy: NSColor(hex: 0xE0A82E)
        case .tinyBuddy: NSColor(hex: 0xFF9E3D)
        }
    }

    /// 동료 그림 (Kenney Pixel Platformer Characters). 두 장을 번갈아 걷는다.
    var buddyFrames: [String]? { Self.buddyFrameNames[self] }

    private static let buddyFrameNames: [Cosmetic: [String]] = Dictionary(uniqueKeysWithValues: allCases.compactMap { item in
        item.buddyTiles.map { (item, $0.map { String(format: "buddy_%04d", $0) }) }
    })

    private var buddyTiles: [Int]? {
        let tiles: [Int]
        switch self {
        case .greenBuddy: tiles = [0, 1]
        case .blueBuddy: tiles = [2, 3]
        case .pinkBuddy: tiles = [4, 5]
        case .yellowBuddy: tiles = [6, 7]
        case .beigeBuddy: tiles = [9, 10]
        case .boxBuddy: tiles = [11, 12]
        case .tinyBuddy: tiles = [13, 14]
        default: return nil
        }
        return tiles
    }
}

/// 상점에서 단계별로 사는 능력. 단계마다 값이 오른다.
enum Ability: String, CaseIterable, Identifiable {
    case airJump, shield, magnet, glide

    var id: String { rawValue }

    var name: String {
        switch self {
        case .airJump: "이단 점프"
        case .shield: "보호막"
        case .magnet: "자석"
        case .glide: "글라이드"
        }
    }

    var icon: String {
        switch self {
        case .airJump: "arrow.up.to.line"
        case .shield: "shield.lefthalf.filled"
        case .magnet: "dot.circle.and.hand.point.up.left.fill"
        case .glide: "wind"
        }
    }

    /// 단계별 값. 개수가 최대 단계다.
    var prices: [Int] {
        switch self {
        case .airJump: [600, 1800]
        case .shield: [300, 800, 1500]
        case .magnet: [250, 600, 1100]
        case .glide: [500]
        }
    }

    var maxLevel: Int { prices.count }

    func detail(level: Int) -> String {
        switch self {
        case .airJump: level >= 2 ? "공중에서 두 번 더 뛰기" : "공중에서 한 번 더 뛰기"
        case .shield: "한 판에 \(max(level, 1))번 부딪혀도 버팀"
        case .magnet: "가까운 코인을 끌어옴 (범위 \(max(level, 1))단계)"
        case .glide: "뛴 채 누르고 있으면 천천히 내려옴"
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
        static let abilityLevels = "gameAbilityLevels"
        static let abilitiesOff = "gameAbilitiesOff"
        static let weekly = "gameWeeklyChallenges"
        static let achievements = "gameAchievements"
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
    @Published private var storedWeekly: DailyMissions
    @Published private(set) var achievements: Achievements {
        didSet { if let data = try? JSONEncoder().encode(achievements) { defaults.set(data, forKey: Key.achievements) } }
    }
    /// 능력별 산 단계와, 사 두고 끈 능력.
    @Published private(set) var abilityLevels: [String: Int] {
        didSet { defaults.set(abilityLevels, forKey: Key.abilityLevels) }
    }
    @Published private(set) var abilitiesOff: Set<String> {
        didSet { defaults.set(Array(abilitiesOff), forKey: Key.abilitiesOff) }
    }
    /// 산 색("theme:gold").
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
        abilityLevels = defaults.dictionary(forKey: Key.abilityLevels) as? [String: Int] ?? [:]
        abilitiesOff = Set(defaults.stringArray(forKey: Key.abilitiesOff) ?? [])
        stored = defaults.data(forKey: Key.missions).flatMap { try? JSONDecoder().decode(DailyMissions.self, from: $0) }
            ?? DailyMissions(day: Self.today())
        storedWeekly = defaults.data(forKey: Key.weekly).flatMap { try? JSONDecoder().decode(DailyMissions.self, from: $0) }
            ?? .week(Self.thisWeek())
        achievements = defaults.data(forKey: Key.achievements).flatMap { try? JSONDecoder().decode(Achievements.self, from: $0) }
            ?? Achievements()
    }

    /// 이번 주 (ISO 주, 월요일 시작). yyyyww.
    static func thisWeek(_ date: Date = Date()) -> Int {
        let parts = Calendar(identifier: .iso8601).dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (parts.yearForWeekOfYear ?? 0) * 100 + (parts.weekOfYear ?? 0)
    }

    /// 이번 주 도전. 주가 바뀌었으면 새 도전.
    var weekly: DailyMissions {
        let week = Self.thisWeek()
        return storedWeekly.day == week ? storedWeekly : .week(week)
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

    /// 미션·도전·업적을 채워 받은 보상.
    struct Reward: Equatable {
        let title: String
        let coins: Int
    }

    /// 판이 끝났다. 먹은 코인을 넣고, 새로 채운 미션·주간 도전·업적의 보상을 더해 그 목록을 돌려준다.
    func finishRun(_ run: DailyMissions.Run, bonusCoins: Int = 0) -> [Reward] {
        var board = missions
        let daily = board.record(run)
        stored = board
        if let data = try? JSONEncoder().encode(board) { defaults.set(data, forKey: Key.missions) }
        var week = weekly
        let challenges = week.record(run)
        storedWeekly = week
        if let data = try? JSONEncoder().encode(week) { defaults.set(data, forKey: Key.weekly) }
        var book = achievements
        let tiers = book.record(run, missionsDone: daily.count + challenges.count)
        achievements = book
        let rewards = daily.map { Reward(title: $0.title(weekly: false), coins: $0.reward) }
            + challenges.map { Reward(title: $0.title(weekly: true), coins: $0.reward) }
            + tiers.map { Reward(title: $0.title, coins: $0.reward) }
        coins += run.coins + bonusCoins + rewards.reduce(0) { $0 + $1.coins }
        return rewards
    }

    func level(_ ability: Ability) -> Int { min(abilityLevels[ability.rawValue] ?? 0, ability.maxLevel) }
    func isOn(_ ability: Ability) -> Bool { level(ability) > 0 && !abilitiesOff.contains(ability.rawValue) }

    /// 다음 단계 값. 최대면 nil.
    func nextPrice(_ ability: Ability) -> Int? {
        let current = level(ability)
        return current < ability.maxLevel ? ability.prices[current] : nil
    }

    /// 다음 단계를 산다. 산 능력은 바로 켠다.
    @discardableResult
    func upgrade(_ ability: Ability) -> Bool {
        guard let price = nextPrice(ability), coins >= price else { return false }
        coins -= price
        abilityLevels[ability.rawValue] = level(ability) + 1
        abilitiesOff.remove(ability.rawValue)
        return true
    }

    func toggle(_ ability: Ability) {
        guard level(ability) > 0 else { return }
        if abilitiesOff.contains(ability.rawValue) { abilitiesOff.remove(ability.rawValue) } else { abilitiesOff.insert(ability.rawValue) }
    }

    /// 다음 판에 쓸 능력 (켜 둔 것만).
    var abilities: RunnerGame.Abilities {
        RunnerGame.Abilities(airJumps: isOn(.airJump) ? level(.airJump) : 0,
                             shields: isOn(.shield) ? level(.shield) : 0,
                             magnet: isOn(.magnet) ? level(.magnet) : 0,
                             glide: isOn(.glide))
    }

    func owns(_ theme: SpriteTheme) -> Bool { theme.price == nil || unlocked.contains("theme:\(theme.rawValue)") }

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
    var title: String { title(weekly: false) }

    func title(weekly: Bool) -> String {
        let text = switch kind {
        case .coins: "코인 \(target)개 먹기"
        case .nearMisses: "아슬! \(target)번"
        case .score: "한 판 \(target)점 넘기"
        case .plays: "\(target)판 하기"
        case .jumps: "\(target)번 뛰기"
        case .ghostWins: target == 1 ? "고스트 이기기" : "고스트 \(target)번 이기기"
        case .totalScore: "점수 합 \(target.formatted())점"
        }
        return weekly ? "주간 · \(text)" : text
    }

    var icon: String {
        switch kind {
        case .coins: "dollarsign.circle.fill"
        case .nearMisses: "bolt.fill"
        case .score: "flag.checkered"
        case .plays: "gamecontroller.fill"
        case .jumps: "arrow.up.circle.fill"
        case .ghostWins: "person.2.fill"
        case .totalScore: "sum"
        }
    }
}

extension Achievements.Kind {
    var name: String {
        switch self {
        case .plays: "꾸준한 러너"
        case .coins: "코인 수집가"
        case .bestScore: "기록 사냥꾼"
        case .jumps: "점프 장인"
        case .nearMisses: "아슬아슬 달인"
        case .ghostWins: "고스트 버스터"
        case .missions: "미션 해결사"
        }
    }

    func goal(_ target: Int) -> String {
        let n = target.formatted()
        return switch self {
        case .plays: "\(n)판 달리기"
        case .coins: "코인 \(n)개 모으기"
        case .bestScore: "한 판 \(n)점"
        case .jumps: "\(n)번 뛰기"
        case .nearMisses: "아슬! \(n)번"
        case .ghostWins: "고스트 \(n)번 이기기"
        case .missions: "미션·도전 \(n)개 채우기"
        }
    }

    var icon: String {
        switch self {
        case .plays: "figure.run"
        case .coins: "dollarsign.circle.fill"
        case .bestScore: "trophy.fill"
        case .jumps: "arrow.up.circle.fill"
        case .nearMisses: "bolt.fill"
        case .ghostWins: "person.2.fill"
        case .missions: "checklist"
        }
    }
}

extension Achievements.Tier {
    static let numerals = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ"]

    var title: String { "업적 · \(kind.name) \(Self.numerals[min(level, Self.numerals.count - 1)])" }
}

extension SpriteTheme {
    /// 고를 수 있는 색: 기본 색과 산 색. 지금 고른 색은 늘 넣는다.
    static func owned(current: SpriteTheme) -> [SpriteTheme] {
        allCases.filter { GameWallet.shared.owns($0) || $0 == current }
    }
}

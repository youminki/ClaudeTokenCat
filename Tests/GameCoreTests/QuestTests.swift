import Foundation
import Testing
@testable import GameCore

@Suite struct WeeklyChallengeTests {
    static let before20261009: [DailyMissions.Kind] = [.score, .plays, .jumps]

    @Test func weeklyIsStableAndDiffersFromDaily() {
        #expect(DailyMissions.week(202641).missions == DailyMissions.week(202641).missions)
        #expect(DailyMissions.week(202641).isWeekly)
        #expect(!DailyMissions(day: 20261009).isWeekly)
        for week in 202601...202652 {
            let kinds = DailyMissions.week(week).missions.map(\.kind)
            #expect(Set(kinds).count == 3)
        }
        // 주간 도전이 생기기 전과 같은 미션 (2026-10-09에 앱이 보여 준 것)
        #expect(DailyMissions(day: 20261009).missions.map(\.kind) == Self.before20261009)
        // 하루 미션에는 점수 합 미션이 나오지 않는다
        for day in 20261001...20261031 {
            #expect(!DailyMissions(day: day).missions.contains { $0.kind == .totalScore })
        }
    }

    @Test func totalScoreAddsUp() {
        var board = DailyMissions.week(202641)
        for _ in 0..<5 { _ = board.record(DailyMissions.Run(score: 500)) }
        if let i = board.missions.firstIndex(where: { $0.kind == .totalScore }) {
            #expect(board.progress[i] == 2500)
        }
    }

    @Test func oldSavedBoardDecodesAsDaily() throws {
        let json = #"{"day":20261009,"missions":[{"kind":"coins","target":30,"reward":20}],"progress":[5]}"#
        let board = try JSONDecoder().decode(DailyMissions.self, from: Data(json.utf8))
        #expect(!board.isWeekly)
        #expect(board.progress == [5])
    }
}

@Suite struct AchievementsTests {
    @Test func reachesTiersInOrderOnce() {
        var book = Achievements()
        var rewards: [Int] = []
        for _ in 0..<9 { rewards += book.record(DailyMissions.Run(score: 10)).filter { $0.kind == .plays }.map(\.reward) }
        #expect(rewards.isEmpty)
        let tenth = book.record(DailyMissions.Run(score: 10))
        #expect(tenth.contains { $0.kind == .plays && $0.level == 0 && $0.reward == Achievements.rewards[0] })
        #expect(book.levels(.plays) == 1)
        #expect(book.next(.plays)?.target == 50)
    }

    @Test func oneBigRunCanPassSeveralTiers() {
        var book = Achievements()
        let tiers = book.record(DailyMissions.Run(score: 2500))
        #expect(tiers.filter { $0.kind == .bestScore }.map(\.level) == [0, 1, 2])
        #expect(book.record(DailyMissions.Run(score: 100)).filter { $0.kind == .bestScore }.isEmpty)
        #expect(book.value(.bestScore) == 2500)
    }

    @Test func roundTripsThroughJSON() throws {
        var book = Achievements()
        _ = book.record(DailyMissions.Run(coins: 120, jumps: 30), missionsDone: 2)
        let copy = try JSONDecoder().decode(Achievements.self, from: JSONEncoder().encode(book))
        #expect(copy == book)
        #expect(copy.value(.missions) == 2)
    }

    @Test func unknownSavedKindDoesNotDropProgress() throws {
        let json = #"{"totals":{"plays":12,"newKind":5},"reached":{"plays":1,"newKind":2}}"#
        let book = try JSONDecoder().decode(Achievements.self, from: Data(json.utf8))
        #expect(book.value(.plays) == 12)
        #expect(book.levels(.plays) == 1)
    }

    @Test func stopsAfterLastTier() {
        var book = Achievements()
        _ = book.record(DailyMissions.Run(score: 99_999))
        #expect(book.next(.bestScore) == nil)
        #expect(book.levels(.bestScore) == Achievements.maxLevel(.bestScore))
    }
}

import Testing
@testable import GameCore

@Suite struct DailyMissionsTests {
    @Test func sameDaySameMissionsAndDistinctKinds() {
        #expect(DailyMissions(day: 20261009).missions == DailyMissions(day: 20261009).missions)
        for day in 20261001...20261031 {
            let kinds = DailyMissions(day: day).missions.map(\.kind)
            #expect(kinds.count == 3)
            #expect(Set(kinds).count == 3)
        }
        let days = (20261001...20261031).map { DailyMissions(day: $0).missions.map(\.kind) }
        #expect(Set(days.map { $0.map(\.rawValue).joined() }).count > 5)
    }

    @Test func completesOnceAndScoreIsBestRunNotSum() {
        var board = DailyMissions(day: 20261009)
        let run = DailyMissions.Run(coins: 40, nearMisses: 4, score: 350, jumps: 60, wonRace: true)
        var completedTotal = 0
        for _ in 0..<10 { completedTotal += board.record(run).count }
        #expect(completedTotal == board.doneCount)
        if let i = board.missions.firstIndex(where: { $0.kind == .score }) {
            #expect(board.progress[i] == 350)
        }
    }
}

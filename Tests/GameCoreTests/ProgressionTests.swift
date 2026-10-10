import Testing
@testable import GameCore

@Suite struct RunnerLevelTests {
    @Test func levelsUpAndCarriesOverflow() {
        var level = RunnerLevel()
        #expect(level.add(99).isEmpty)
        #expect(level.add(1) == [2])
        #expect(level.xp == 0)
        // 140 + 180 + 남은 10 → 레벨 4, 10
        #expect(level.add(330) == [3, 4])
        #expect(level.level == 4 && level.xp == 10)
    }

    @Test func xpAndRewards() {
        #expect(RunnerLevel.xp(for: DailyMissions.Run(coins: 10, score: 500)) == 75)
        #expect(RunnerLevel.reward(reaching: 5).box)
        #expect(!RunnerLevel.reward(reaching: 4).box)
    }
}

@Suite struct AttendanceTests {
    @Test func streakContinuesAndResets() {
        var a = Attendance()
        #expect(a.check(in: 100) == 1)
        #expect(a.check(in: 100) == nil)        // 같은 날 두 번째 판
        #expect(a.check(in: 101) == 2)
        #expect(a.current(on: 102) == 2)        // 아직 오늘 안 했어도 이어지는 중
        #expect(a.current(on: 103) == 0)        // 하루 빠짐
        #expect(a.check(in: 103) == 1)
    }

    @Test func seventhDayGivesBox() {
        #expect(Attendance.reward(day: 7).box)
        #expect(Attendance.reward(day: 8) == (20, false))
        #expect(!Attendance.reward(day: 6).box)
    }
}

@Suite struct LuckyBoxTests {
    let items: [(item: String, rarity: Rarity)] = [("a", .common), ("b", .common), ("c", .rare), ("d", .legendary)]

    @Test func weightsByRarity() {
        #expect(LuckyBox.pick(from: items, roll: 0.0, second: 0) == "a")
        #expect(LuckyBox.pick(from: items, roll: 0.0, second: 0.99) == "b")
        // 남은 등급 가중치 60+28+2=90. 0.7*90=63 → 희귀
        #expect(LuckyBox.pick(from: items, roll: 0.7, second: 0) == "c")
        #expect(LuckyBox.pick(from: items, roll: 0.999, second: 0) == "d")
    }

    @Test func emptyRarityIsSkippedAndEmptyListGivesNil() {
        let onlyEpic: [(item: String, rarity: Rarity)] = [("e", .epic)]
        #expect(LuckyBox.pick(from: onlyEpic, roll: 0.01, second: 0) == "e")
        #expect(LuckyBox.pick(from: [(item: String, rarity: Rarity)](), roll: 0.5, second: 0.5) == nil)
    }
}

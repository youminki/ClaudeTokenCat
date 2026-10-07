import Testing
@testable import GameCore

/// 키는 따로 주지 않으면 이름과 같게 둔다.
private func snap(top: String? = "A", topKey: String? = nil, score: Int? = 100, you: Bool = false,
                  week: String? = "A", weekKey: String? = nil, weekScore: Int? = 100, weekYou: Bool = false,
                  rank: Int? = 3) -> RankSnapshot {
    RankSnapshot(topKey: topKey ?? top, topName: top, topScore: score, topIsYou: you, weekTopKey: weekKey ?? week,
                 weekTopName: week, weekTopScore: weekScore, weekTopIsYou: weekYou, myRank: rank)
}

@Suite struct RankFeedTests {
    @Test func firstSummaryIsOnlyABaseline() {
        #expect(RankFeed.news(from: nil, to: snap()).isEmpty)
    }

    @Test func nothingChangedNothingToSay() {
        #expect(RankFeed.news(from: snap(), to: snap()).isEmpty)
    }

    @Test func someoneElseTakesFirstPlace() {
        let news = RankFeed.news(from: snap(), to: snap(top: "B", score: 150, week: "B", weekScore: 150))
        #expect(news == [.newChampion(name: "B", score: 150)], "같은 사람의 이번 주 1위는 겹쳐 말하지 않는다")
    }

    @Test func championRaisesOwnRecord() {
        #expect(RankFeed.news(from: snap(), to: snap(score: 130, weekScore: 130)) == [.championImproved(name: "A", score: 130)])
    }

    @Test func iBecomeChampionOnce() {
        let before = snap(rank: 2)
        let after = snap(top: "나", score: 200, you: true, week: "나", weekScore: 200, weekYou: true, rank: 1)
        #expect(RankFeed.news(from: before, to: after) == [.youAreChampion(score: 200)])
        #expect(RankFeed.news(from: after, to: after).isEmpty)
    }

    @Test func renamingChampionIsNotNews() {
        let renamed = snap(top: "A2", topKey: "A", week: "A2", weekKey: "A")
        #expect(RankFeed.news(from: snap(), to: renamed).isEmpty)
    }

    @Test func sameNicknameDifferentPersonIsNewChampion() {
        let other = snap(top: "A", topKey: "other", week: "A", weekKey: "other")
        #expect(RankFeed.news(from: snap(), to: other) == [.newChampion(name: "A", score: 100)])
    }

    @Test func oldSnapshotWithoutKeysStillCompares() {
        let old = RankSnapshot(topName: "A", topScore: 100, topIsYou: false, weekTopName: "A", weekTopScore: 100,
                               weekTopIsYou: false, myRank: 3)
        #expect(RankFeed.news(from: old, to: old).isEmpty)
        // 새 요약에 키가 생겨도 예전 저장값과는 닉네임으로 견준다
        #expect(RankFeed.news(from: old, to: snap(topKey: "a1b2", weekKey: "a1b2")).isEmpty)
    }

    @Test func weeklyChampionDifferentFromAllTime() {
        #expect(RankFeed.news(from: snap(), to: snap(week: "C", weekScore: 80)) == [.newWeeklyChampion(name: "C", score: 80)])
    }

    @Test func overtakenReportsRanks() {
        #expect(RankFeed.news(from: snap(rank: 3), to: snap(rank: 5)) == [.overtaken(from: 3, to: 5)])
        #expect(RankFeed.news(from: snap(rank: 5), to: snap(rank: 3)).isEmpty, "올라간 것은 판이 끝날 때 따로 알린다")
    }

    @Test func losingFirstPlaceIsToldOnceAsNewChampion() {
        let before = snap(top: "나", score: 200, you: true, week: "나", weekScore: 200, weekYou: true, rank: 1)
        let after = snap(top: "B", score: 250, week: "B", weekScore: 250, rank: 2)
        #expect(RankFeed.news(from: before, to: after) == [.newChampion(name: "B", score: 250)])
    }
}

@Suite struct RivalTrackerTests {
    @Test func passesRivalsInOrderAndPointsToNext() {
        var tracker = RivalTracker(rivals: [Rival(name: "c", score: 300), Rival(name: "a", score: 100),
                                            Rival(name: "b", score: 200), Rival(name: "zero", score: 0)])
        #expect(tracker.next?.name == "a")
        #expect(tracker.update(score: 50).isEmpty)
        #expect(tracker.update(score: 250).map(\.name) == ["a", "b"])
        #expect(tracker.next?.name == "c")
        #expect(tracker.update(score: 300).isEmpty, "같은 점수는 아직 못 넘었다")
        #expect(tracker.update(score: 301).map(\.name) == ["c"])
        #expect(tracker.next == nil)
    }
}

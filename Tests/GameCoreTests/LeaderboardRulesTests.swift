import Testing
@testable import GameCore

/// 순위 서버(server/leaderboard/src/rules.js)의 규칙 1과 같은 숫자인지. 한쪽만 바꾸면 정직한 점수가 거절된다.
@Suite struct LeaderboardRulesTests {
    @Test func rulesOneMatchesServer() {
        let tuning = RunnerGame.Tuning()
        #expect(RunnerGame.rulesVersion == 1)
        #expect(tuning.startSpeed == 220)
        #expect(tuning.maxSpeed == 440)
        #expect(tuning.acceleration == 6)
        #expect(tuning.scorePerPoint == 0.04)
        #expect(tuning.coinValue == 10)
        // 서버는 장애물 사이를 0.7초 이상으로 본다
        #expect(tuning.airTime + tuning.reactionTime - 0.03 >= 0.7)
    }
}

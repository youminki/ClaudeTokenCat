/// 스스로 하는 플레이어. 꼭대기까지 누르고 뛰되, 점프 궤적의 가운데가 장애물 가운데에 오게 뛴다.
/// 서서 지나갈 수 있는 높이 뜬 장애물은 뛰지 않는다. 규칙 테스트와 화면 점검 도구가 쓴다.
public final class Autopilot {
    private let game: RunnerGame
    private var holding = false

    public init(game: RunnerGame) {
        self.game = game
    }

    /// 한 장면 전에 부른다. 누르거나 뗄 때를 정한다.
    public func step() {
        guard game.phase == .playing else { return }
        if holding, !game.isOnGround, game.velocityY <= 0 {
            game.release()
            holding = false
        }
        let runner = game.runnerBox
        guard !holding, game.isOnGround,
              let next = game.obstacles.first(where: { $0.x + $0.width > runner.minX }) else { return }
        let closing = game.speed + next.kind.approachSpeed
        let underneath = next.y + game.tuning.hitInset >= game.runnerHeight + 2
        let lead = (closing * game.tuning.airTime - next.width - game.runnerWidth) / 2
        if !underneath, next.x - runner.maxX < max(lead, 4) {
            game.press()
            holding = true
        }
    }
}

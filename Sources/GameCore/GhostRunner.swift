/// 기록해 둔 판을 같은 씨앗과 같은 틱의 입력으로 다시 돌린다. 규칙이 고정 간격이라 처음 판과 똑같이 움직인다.
public final class GhostRunner {
    public let game: RunnerGame
    private let inputs: [RunnerGame.InputRecord]
    private var next = 0

    public init(tuning: RunnerGame.Tuning, runnerWidth: Double, runnerHeight: Double, seed: UInt64,
                inputs: [RunnerGame.InputRecord]) {
        game = RunnerGame(tuning: tuning, runnerWidth: runnerWidth, runnerHeight: runnerHeight, seed: seed)
        self.inputs = inputs
        apply(upTo: 0)   // 시작 전에 누르고 있던 키와 시작 입력
        game.beforeTick = { [unowned self] tick in self.apply(upTo: tick) }
    }

    public func advance(by seconds: Double) {
        game.advance(by: seconds)
    }

    private func apply(upTo tick: Int) {
        while next < inputs.count, inputs[next].tick <= tick {
            game.apply(inputs[next].input)
            next += 1
        }
    }
}

extension GhostRunner {
    /// 끝날 때까지 돌려 본다. 남이 준 고스트의 점수를 믿지 않고 직접 낸 점수를 쓴다.
    /// 상한 안에 끝나지 않으면 nil (일부러 만든 끝없는 기록).
    public func finalScore(maxTicks: Int) -> Int? {
        while game.phase == .playing, game.ticks < maxTicks { advance(by: RunnerGame.step) }
        return game.phase == .over ? game.score : nil
    }
}

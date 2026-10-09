import Foundation
import GameCore

/// 최고 판의 씨앗과 입력. 고스트와 겨룰 때 같은 코스를 만들고 그때 움직임을 그대로 다시 돌린다.
struct GhostRecord: Codable {
    /// JSON 숫자는 2^53을 넘으면 어긋날 수 있어 글자로 둔다.
    let seed: String
    let score: Int
    /// 규칙·장애물 목록이 바뀌면 같은 입력으로 다른 판이 나오니, 저장할 때의 규칙을 함께 둔다.
    let layout: String
    let inputs: [RunnerGame.InputRecord]

    var seedValue: UInt64? { UInt64(seed) }
}

/// 이 Mac에만 저장한다.
enum GhostStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RunTime/ghost.json")
    }

    static func layout(of game: RunnerGame) -> String {
        "\(RunnerGame.rulesVersion) \(game.runnerWidth)x\(game.runnerHeight) \(String(describing: game.tuning))"
    }

    /// 지금 규칙으로 다시 돌릴 수 있는 고스트만.
    static func load(for game: RunnerGame) -> GhostRecord? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(GhostRecord.self, from: data),
              record.layout == layout(of: game), record.seedValue != nil
        else { return nil }
        return record
    }

    /// 방금 끝난 판을 고스트로 남긴다.
    @discardableResult
    static func save(_ game: RunnerGame) -> GhostRecord? {
        let record = GhostRecord(seed: String(game.seed), score: game.score, layout: layout(of: game),
                                 inputs: game.inputLog)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            return record
        } catch {
            NSLog("[RunTime] 고스트 저장 실패: %@", error.localizedDescription)
            return nil
        }
    }
}

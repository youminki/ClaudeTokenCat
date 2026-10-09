import Foundation
import GameCore

/// 한 판의 씨앗과 입력. 고스트와 겨룰 때 같은 코스를 만들고 그때 움직임을 그대로 다시 돌린다.
struct GhostRecord: Codable {
    /// JSON 숫자는 2^53을 넘으면 어긋날 수 있어 글자로 둔다.
    let seed: String
    let score: Int
    /// 규칙·장애물 목록이 바뀌면 같은 입력으로 다른 판이 나오니, 저장할 때의 규칙을 함께 둔다.
    let layout: String
    let inputs: [RunnerGame.InputRecord]
    /// 그 판을 달린 러너 (AppSettings.runnerID). 고스트를 이 러너 모습으로 그린다.
    var runner: String?
    /// 순위 고스트의 닉네임과 등수. 내 고스트는 nil.
    var name: String?
    var rank: Int?

    var seedValue: UInt64? { UInt64(seed) }
}

/// 내 최고 판 고스트. 이 Mac에만 저장한다.
enum GhostStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RunTime/ghost.json")
    }

    /// 남의 고스트를 확인할 때 돌려 보는 상한 (1시간).
    static let maxReplayTicks = Int(3600 / RunnerGame.step)

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

    static func record(of game: RunnerGame, runner: String?) -> GhostRecord {
        GhostRecord(seed: String(game.seed), score: game.score, layout: layout(of: game), inputs: game.inputLog,
                    runner: runner)
    }

    /// 방금 끝난 판을 내 고스트로 남긴다.
    static func save(_ record: GhostRecord) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("[RunTime] 고스트 저장 실패: %@", error.localizedDescription)
            return false
        }
    }

    /// 순위 서버로 보낼 입력. JSON을 압축해 base64로 싼다.
    static func packInputs(_ inputs: [RunnerGame.InputRecord]) -> String? {
        guard let json = try? JSONEncoder().encode(inputs),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return packed.base64EncodedString()
    }

    static func unpackInputs(_ text: String) -> [RunnerGame.InputRecord]? {
        guard let packed = Data(base64Encoded: text),
              let json = try? (packed as NSData).decompressed(using: .zlib) as Data
        else { return nil }
        return try? JSONDecoder().decode([RunnerGame.InputRecord].self, from: json)
    }

    /// 끝까지 돌려 본 점수가 적힌 점수와 같은 고스트만 믿는다. 오래 걸릴 수 있어 메인 스레드 밖에서 부른다.
    static func verified(_ record: GhostRecord, tuning: RunnerGame.Tuning, runnerWidth: Double, runnerHeight: Double) -> Bool {
        guard let seed = record.seedValue else { return false }
        let ghost = GhostRunner(tuning: tuning, runnerWidth: runnerWidth, runnerHeight: runnerHeight,
                                seed: seed, inputs: record.inputs)
        return ghost.finalScore(maxTicks: maxReplayTicks) == record.score
    }
}

/// 순위 1위(고스트를 올린 사람 가운데 가장 높은 점수)의 고스트. 게임을 켤 때 받아 두고 1분마다 새로 받는다.
final class TopGhost {
    static let all = TopGhost(.all)
    static let week = TopGhost(.week)

    let period: Leaderboard.Period
    private(set) var record: GhostRecord?

    private init(_ period: Leaderboard.Period) {
        self.period = period
    }
    private var fetchedAt: Date?
    private var loading = false

    /// 이 규칙으로 돌릴 수 있고, 돌려 본 점수가 순위 점수와 같은 고스트만 둔다.
    func refresh(for game: RunnerGame) {
        guard !loading, Leaderboard.shared.isAvailable,
              fetchedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        loading = true
        let layout = GhostStore.layout(of: game)
        let tuning = game.tuning, width = game.runnerWidth, height = game.runnerHeight
        Leaderboard.shared.fetchTopGhost(period) { [weak self] result in
            guard let self else { return }
            self.fetchedAt = Date()
            guard case .success(let remote) = result, let remote, remote.layout == layout,
                  let inputs = GhostStore.unpackInputs(remote.inputs)
            else {
                if case .success = result { self.record = nil }   // 서버에 없으면 지운다 (실패면 둔다)
                self.loading = false
                return
            }
            let record = GhostRecord(seed: remote.seed, score: remote.score, layout: remote.layout, inputs: inputs,
                                     runner: remote.runner, name: remote.nickname, rank: remote.rank)
            DispatchQueue.global(qos: .utility).async {
                let ok = GhostStore.verified(record, tuning: tuning, runnerWidth: width, runnerHeight: height)
                DispatchQueue.main.async {
                    self.record = ok ? record : nil
                    self.loading = false
                }
            }
        }
    }
}

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
    /// 고스트 코드로 받은 친구 고스트의 이름 (순위 닉네임). 내 고스트는 nil.
    var name: String?

    var seedValue: UInt64? { UInt64(seed) }
}

/// 이 Mac에만 저장한다.
enum GhostStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RunTime", isDirectory: true)
    }
    private static var url: URL { directory.appendingPathComponent("ghost.json") }
    /// 붙여 넣은 친구 고스트.
    private static var challengeURL: URL { directory.appendingPathComponent("challenge.json") }

    private static let codePrefix = "RUNTIME-GHOST:"
    /// 2시간 판의 입력도 수십 KB 안이라, 이보다 크면 고스트 코드가 아니다 (압축 풀기 폭탄 방지).
    private static let maxCodeLength = 64 * 1024
    /// 남의 고스트를 확인할 때 돌려 보는 상한 (1시간).
    private static let maxReplayTicks = Int(3600 / RunnerGame.step)

    static func layout(of game: RunnerGame) -> String {
        "\(RunnerGame.rulesVersion) \(game.runnerWidth)x\(game.runnerHeight) \(String(describing: game.tuning))"
    }

    /// 지금 규칙으로 다시 돌릴 수 있는 고스트만.
    static func load(for game: RunnerGame) -> GhostRecord? { read(url, for: game) }

    static func loadChallenge(for game: RunnerGame) -> GhostRecord? { read(challengeURL, for: game) }

    private static func read(_ url: URL, for game: RunnerGame) -> GhostRecord? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(GhostRecord.self, from: data),
              record.layout == layout(of: game), record.seedValue != nil
        else { return nil }
        return record
    }

    /// 친구에게 보낼 한 줄 코드. JSON을 압축해 base64로 싼다.
    static func code(for record: GhostRecord, name: String?) -> String? {
        var shared = record
        shared.name = name.flatMap { $0.isEmpty ? nil : $0 }
        guard let json = try? JSONEncoder().encode(shared),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data
        else { return nil }
        return codePrefix + packed.base64EncodedString()
    }

    enum CodeError: LocalizedError {
        case notACode, otherRules, broken

        var errorDescription: String? {
            switch self {
            case .notACode: "고스트 코드가 아니에요"
            case .otherRules: "다른 버전에서 만든 고스트예요"
            case .broken: "끝까지 돌려 볼 수 없는 고스트예요"
            }
        }
    }

    /// 붙여 넣은 코드를 읽고, 직접 끝까지 돌려 본 점수로 바꾼다.
    static func readCode(_ text: String, for game: RunnerGame) -> Result<GhostRecord, CodeError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(codePrefix), trimmed.count <= maxCodeLength,
              let packed = Data(base64Encoded: String(trimmed.dropFirst(codePrefix.count))),
              let json = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let record = try? JSONDecoder().decode(GhostRecord.self, from: json),
              let seed = record.seedValue
        else { return .failure(.notACode) }
        guard record.layout == layout(of: game) else { return .failure(.otherRules) }
        let ghost = GhostRunner(tuning: game.tuning, runnerWidth: game.runnerWidth, runnerHeight: game.runnerHeight,
                                seed: seed, inputs: record.inputs)
        guard let score = ghost.finalScore(maxTicks: maxReplayTicks) else { return .failure(.broken) }
        let name = record.name.map { String($0.prefix(12)) }
        return .success(GhostRecord(seed: record.seed, score: score, layout: record.layout, inputs: record.inputs, name: name))
    }

    static func saveChallenge(_ record: GhostRecord) {
        write(record, to: challengeURL)
    }

    /// 방금 끝난 판을 고스트로 남긴다.
    @discardableResult
    static func save(_ game: RunnerGame) -> GhostRecord? {
        let record = GhostRecord(seed: String(game.seed), score: game.score, layout: layout(of: game),
                                 inputs: game.inputLog)
        return write(record, to: url) ? record : nil
    }

    @discardableResult
    private static func write(_ record: GhostRecord, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("[RunTime] 고스트 저장 실패: %@", error.localizedDescription)
            return false
        }
    }
}

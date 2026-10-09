import CryptoKit
import Foundation
import GameCore

/// 미니게임 순위 (서버: server/leaderboard, Cloudflare Workers + D1).
/// 순위 참여를 켠 사람만, 최근 7일 동안 보낸 점수보다 높을 때 무작위 설치 ID·닉네임·점수·코인·플레이 시간·앱 버전을 보낸다.
/// (역대 최고만 보내면 이번 주 순위표가 시간이 갈수록 빈다. 서버의 주간 순위도 최근 7일 기준이다.)
/// 사용량이나 Claude 토큰은 보내지 않는다. 메인 스레드에서만 쓴다.
final class Leaderboard: ObservableObject {
    static let shared = Leaderboard()

    /// 배포한 순위 서버 주소. 비어 있으면 순위 기능을 숨긴다.
    /// 직접 띄운 서버로 바꾸려면 `defaults write dev.runtime.RunTime leaderboardURL <주소>`.
    static let serverURL = URL(string: "https://tokencat-leaderboard.youminki.workers.dev")

    private enum Key {
        static let on = "leaderboardOn", name = "leaderboardName", player = "leaderboardPlayer"
        static let weekBest = "leaderboardWeekBest", weekBestAt = "leaderboardWeekBestAt", url = "leaderboardURL"
    }

    private let defaults = UserDefaults.standard
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    @Published var isOn: Bool { didSet { defaults.set(isOn, forKey: Key.on) } }
    @Published var nickname: String { didSet { defaults.set(nickname, forKey: Key.name) } }
    /// 이 Mac의 무작위 ID. 순위에서 내 줄을 찾고 기록을 지울 때 쓴다.
    let playerID: String

    private init() {
        isOn = defaults.bool(forKey: Key.on)
        nickname = defaults.string(forKey: Key.name) ?? ""
        if let saved = defaults.string(forKey: Key.player), UUID(uuidString: saved) != nil {
            playerID = saved
        } else {
            playerID = UUID().uuidString
            defaults.set(playerID, forKey: Key.player)
        }
    }

    /// 끝에 /가 있어야 상대 경로가 주소의 경로 뒤에 붙는다 (https://host/api → https://host/api/v1/...).
    /// 서버가 순위 줄마다 붙이는 사람 키와 같은 값 (server/leaderboard의 playerKey). 참여하지 않아 ID를 보내지 않아도
    /// 라이벌 중 누가 나인지, 1위가 나인지 알 수 있다.
    var playerKey: String {
        // 서버에 이미 쌓인 기록과 같은 키가 나와야 해서 옛 이름을 그대로 쓴다
        SHA256.hash(data: Data("tokencat:\(playerID)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    var baseURL: URL? {
        let custom = defaults.string(forKey: Key.url).flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 }
        guard let url = custom ?? Self.serverURL else { return nil }
        return url.absoluteString.hasSuffix("/") ? url : URL(string: url.absoluteString + "/")
    }

    var isAvailable: Bool { baseURL != nil }

    /// 서버(rules.js cleanNickname)와 같은 규칙: NFC로 맞춘 코드포인트 2~12개, 완성형 한글·호환 자모(채움 문자 제외)·
    /// 영문·숫자·공백·_ . -, 공백을 빼고 2자 이상.
    static func normalized(_ nickname: String) -> String {
        nickname.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
    }

    static func isValid(nickname: String) -> Bool {
        let scalars = normalized(nickname).unicodeScalars
        guard (2...12).contains(scalars.count), scalars.filter({ $0 != " " }).count >= 2 else { return false }
        return scalars.allSatisfy { scalar in
            (0xAC00...0xD7A3).contains(scalar.value) || (0x3131...0x3163).contains(scalar.value)
                || (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || " _.-".unicodeScalars.contains(scalar)))
        }
    }

    var canSubmit: Bool { isAvailable && isOn && Self.isValid(nickname: nickname) }

    // MARK: 서버 응답

    struct Submitted: Decodable {
        let best: Int
        let rank: Int
        let total: Int
    }

    struct Board: Decodable {
        struct Entry: Decodable, Identifiable {
            let rank: Int
            let nickname: String
            let score: Int
            let you: Bool
            var id: String { "\(rank)-\(nickname)-\(score)" }
        }

        struct You: Decodable {
            let rank: Int
            let score: Int
        }

        let period: String
        let total: Int
        let entries: [Entry]
        let you: You?
    }

    /// 주기적으로 받는 요약 (GET /v1/summary).
    struct Summary: Decodable {
        struct Champion: Decodable {
            let nickname: String
            let score: Int
            let key: String
        }

        struct Player: Decodable {
            let nickname: String
            let score: Int
            let key: String
        }

        let top: Champion?
        let weekTop: Champion?
        let total: Int
        let you: Board.You?
        /// 나를 뺀 상위 점수들과 내 바로 위 사람들, 높은 점수부터.
        let rivals: [Player]
    }

    private struct ServerMessage: Decodable {
        let error: String
    }

    enum Period: String, CaseIterable {
        case all, week

        var title: String { self == .all ? "전체" : "이번 주" }
    }

    enum Failure: LocalizedError {
        case unavailable
        case server(Int, String?)
        case network

        var errorDescription: String? {
            switch self {
            case .unavailable: return "순위 서버가 설정되지 않았습니다."
            case .server(429, _): return "잠시 뒤에 다시 시도하세요."
            case .server(_, let message): return "순위 서버가 거절했습니다\(message.map { " (\($0))" } ?? "")."
            case .network: return "순위 서버에 연결하지 못했습니다."
            }
        }
    }

    // MARK: 요청

    /// 최근 7일 안에 보낸 가장 높은 점수. 그 판이 7일을 넘기면 서버 주간 순위에서도 빠지니 0으로 본다.
    private var weekBest: Int {
        let at = defaults.double(forKey: Key.weekBestAt)
        return Date().timeIntervalSince1970 - at < 7 * 24 * 60 * 60 ? defaults.integer(forKey: Key.weekBest) : 0
    }

    /// 한 판이 끝났을 때. 참여 중이고 최근 7일 안에 보낸 점수보다 높을 때만 보낸다. 보냈으면 true.
    @discardableResult
    func submit(_ game: RunnerGame, completion: @escaping (Result<Submitted, Failure>) -> Void) -> Bool {
        guard canSubmit, game.score > 0, game.score > weekBest else { return false }
        let body: [String: Any] = [
            "player": playerID,
            "nickname": Self.normalized(nickname),
            "score": game.score,
            "coins": game.coinsTaken,
            "durationMs": Int(game.elapsed * 1000),
            "rules": RunnerGame.rulesVersion,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
        ]
        let score = game.score
        request("POST", "v1/runs", body: body) { (result: Result<Submitted, Failure>) in
            if case .success = result {
                self.defaults.set(score, forKey: Key.weekBest)
                self.defaults.set(Date().timeIntervalSince1970, forKey: Key.weekBestAt)
            }
            completion(result)
        }
        return true
    }

    /// 방금 올린 판의 고스트를 올린다. 서버는 역대나 이번 주 최고 점수와 같은 판만 그 기간에 둔다.
    /// 고스트를 받지 않는 옛 서버면 404가 오는데, 순위에는 영향이 없어 무시한다.
    func uploadGhost(_ record: GhostRecord) {
        guard canSubmit, let inputs = GhostStore.packInputs(record.inputs) else { return }
        var body: [String: Any] = ["player": playerID, "score": record.score, "seed": record.seed,
                                   "inputs": inputs, "layout": GhostStore.remoteLayout(record)]
        if let runner = record.runner { body["runner"] = runner }
        struct Saved: Decodable { let saved: Bool }
        request("POST", "v1/ghosts", body: body) { (_: Result<Saved, Failure>) in }
    }

    struct RemoteGhost: Decodable {
        let nickname: String
        let score: Int
        let rank: Int
        let seed: String
        let inputs: String
        let layout: String
        let runner: String?
    }

    /// 그 기간 1위 고스트. 서버에 고스트가 없으면 nil. 공개 정보라 설치 ID를 보내지 않는다.
    func fetchTopGhost(_ period: Period, completion: @escaping (Result<RemoteGhost?, Failure>) -> Void) {
        struct Response: Decodable { let ghost: RemoteGhost? }
        request("GET", "v1/ghosts/top?period=\(period.rawValue)", identify: false) { (result: Result<Response, Failure>) in
            completion(result.map(\.ghost))
        }
    }

    func fetch(_ period: Period, completion: @escaping (Result<Board, Failure>) -> Void) {
        request("GET", "v1/leaderboard?period=\(period.rawValue)&limit=50", identify: isOn, completion: completion)
    }

    /// 참여하지 않으면 설치 ID 없이 공개 정보(1위, 라이벌 점수)만 받는다.
    func fetchSummary(completion: @escaping (Result<Summary, Failure>) -> Void) {
        request("GET", "v1/summary", identify: isOn, completion: completion)
    }

    func rename(completion: @escaping (Result<Void, Failure>) -> Void) {
        struct Renamed: Decodable { let nickname: String }
        request("PUT", "v1/players/\(playerID)", body: ["nickname": Self.normalized(nickname)]) { (result: Result<Renamed, Failure>) in
            completion(result.map { _ in () })
        }
    }

    /// 서버에서 내 기록을 지우고 참여를 끈다.
    func forgetMe(completion: @escaping (Result<Void, Failure>) -> Void) {
        struct Deleted: Decodable { let deleted: Bool }
        request("DELETE", "v1/players/\(playerID)") { (result: Result<Deleted, Failure>) in
            if case .success = result {
                self.isOn = false
                self.defaults.removeObject(forKey: Key.weekBest)
                self.defaults.removeObject(forKey: Key.weekBestAt)
                // 내가 지운 기록 때문에 "새 1위" 같은 소식이 나가지 않게 기준부터 다시 잡는다
                LeaderboardFeed.shared.reset()
            }
            completion(result.map { _ in () })
        }
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil,
                                       identify: Bool = true, completion: @escaping (Result<T, Failure>) -> Void) {
        guard let base = baseURL, let url = URL(string: path, relativeTo: base) else {
            completion(.failure(.unavailable))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("RunTime", forHTTPHeaderField: "User-Agent")
        // 순위표에서 내 줄을 찾는 데 쓴다. 이 ID로 기록을 지울 수 있어 주소(로그에 남는 곳)에는 싣지 않는다
        if identify { request.setValue(playerID, forHTTPHeaderField: "X-Player") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result<T, Failure>
            if error != nil || data == nil {
                result = .failure(.network)
            } else if (200..<300).contains(status), let value = try? JSONDecoder().decode(T.self, from: data!) {
                result = .success(value)
            } else {
                let message = data.flatMap { try? JSONDecoder().decode(ServerMessage.self, from: $0) }?.error
                result = .failure(.server(status, message))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

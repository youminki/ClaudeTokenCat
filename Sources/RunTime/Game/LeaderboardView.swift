import SwiftUI

/// 미니게임 순위표 창. 순위 참여와 닉네임도 여기서 정한다.
struct LeaderboardView: View {
    @ObservedObject private var board = Leaderboard.shared
    @StateObject private var state = LeaderboardState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ranking
            participation
        }
        .padding(16)
        .frame(width: 360, height: 520)
        .onAppear { state.start() }
        .onDisappear { state.stop() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("토큰 러너 순위").font(.headline)
                Text("팝오버 무대의 장애물 피하기 게임").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("기간", selection: $state.period) {
                ForEach(Leaderboard.Period.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { state.load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("새로고침 (열려 있는 동안 30초마다 새로 받습니다)")
        }
    }

    @ViewBuilder
    private var ranking: some View {
        VStack(spacing: 0) {
            if let message = state.message {
                placeholder("exclamationmark.triangle", message)
            } else if let result = state.board {
                if result.entries.isEmpty {
                    placeholder("flag.checkered", state.period == .week ? "이번 주 기록이 아직 없습니다." : "아직 기록이 없습니다.")
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(result.entries) { row($0) }
                        }
                        .padding(6)
                    }
                }
                Divider()
                HStack {
                    if let you = result.you {
                        Text("내 순위 \(you.rank)위 · \(result.total)명 중 · 최고 \(you.score)점")
                    } else {
                        Text("\(result.total)명 참여")
                    }
                    Spacer()
                    if let updated = state.updated {
                        Text("\(updated.formatted(date: .omitted, time: .shortened)) 갱신")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func placeholder(_ systemImage: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 1~3위는 메달 색. 같은 점수 1위가 여럿이어도 먼저 세운 맨 위 한 명에게만 왕관 (요약의 1위와 같은 기준)
    private func row(_ entry: Leaderboard.Board.Entry) -> some View {
        let medal = Self.medal(entry.rank)
        return HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(medal == nil ? Color.secondary : Color.black.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(medal ?? Color.primary.opacity(0.06)))
            Text(entry.nickname).font(.system(size: 12.5, weight: entry.you ? .semibold : .regular)).lineLimit(1)
            if entry.id == state.board?.entries.first?.id {
                Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Self.gold)
            }
            if entry.you {
                Text("나").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            Spacer()
            Text("\(entry.score)").font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(entry.you ? 0.12 : 0)))
    }

    private static let gold = Color(nsColor: NSColor(hex: 0xE0A82E))

    private static func medal(_ rank: Int) -> Color? {
        switch rank {
        case 1: return gold
        case 2: return Color(nsColor: NSColor(hex: 0xB9C0C9))
        case 3: return Color(nsColor: NSColor(hex: 0xCD8C55))
        default: return nil
        }
    }

    private var participation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $board.isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("순위에 참여")
                    Text("무작위 ID, 닉네임, 점수와 플레이 기록을 순위 서버로 보냅니다. 사용량과 Claude 계정 정보는 보내지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .help("참여하면 최근 7일 동안 보낸 점수보다 높을 때 무작위 ID, 닉네임, 점수, 코인 수, 플레이 시간, 앱 버전을 보내고, 순위 소식을 받으려고 10분마다 ID와 함께 순위 요약을 받습니다. 참여하지 않으면 ID 없이 공개 순위만 받습니다.")
            if board.isOn {
                HStack {
                    TextField("", text: $board.nickname, prompt: Text("닉네임 (2~12자)"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Button("이름 바꾸기") { state.rename() }
                        .disabled(!Leaderboard.isValid(nickname: board.nickname))
                        .help("이미 올린 기록의 닉네임도 바꿉니다")
                }
                if !Leaderboard.isValid(nickname: board.nickname) {
                    Text("한글·영문·숫자로 2~12자를 넣어야 점수를 보냅니다.").font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                if let notice = state.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("내 기록 지우기", role: .destructive) { state.forget() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help("서버에서 내 점수와 닉네임을 지우고 참여를 끕니다")
            }
        }
    }
}

/// 순위표 창 상태. `@State`를 못 쓰는 이유는 HoverFlag 참고.
final class LeaderboardState: ObservableObject {
    @Published var period: Leaderboard.Period = .all { didSet { if period != oldValue { load() } } }
    @Published private(set) var board: Leaderboard.Board?
    @Published private(set) var message: String?
    @Published private(set) var notice: String?
    @Published private(set) var updated: Date?
    private var timer: Timer?

    /// 창이 열려 있는 동안 30초마다 새로 받는다. 이미 보이는 표는 받는 동안에도 그대로 둔다.
    func start() {
        load()
        timer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.load(keepVisible: true) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func load(keepVisible: Bool = false) {
        if !keepVisible {
            board = nil
            message = nil
        }
        let period = period
        Leaderboard.shared.fetch(period) { [weak self] result in
            guard let self, self.period == period else { return }
            switch result {
            case .success(let board):
                self.board = board
                self.message = nil
                self.updated = Date()
            case .failure(let error):
                if self.board == nil { self.message = error.localizedDescription }
            }
        }
    }

    func rename() {
        Leaderboard.shared.rename { [weak self] result in
            if case .failure(let error) = result { self?.notice = error.localizedDescription; return }
            self?.notice = "이름을 바꿨습니다."
            self?.load()
        }
    }

    func forget() {
        Leaderboard.shared.forgetMe { [weak self] result in
            if case .failure(let error) = result { self?.notice = error.localizedDescription; return }
            self?.notice = "서버에서 내 기록을 지웠습니다."
            self?.load()
        }
    }
}

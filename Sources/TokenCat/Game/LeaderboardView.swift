import SwiftUI

/// 미니게임 순위표 창. 순위 참여와 닉네임도 여기서 정한다.
struct LeaderboardView: View {
    @ObservedObject private var board = Leaderboard.shared
    @StateObject private var state = LeaderboardState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("토큰 러너 순위").font(.headline)
                Spacer()
                Picker("", selection: $state.period) {
                    ForEach(Leaderboard.Period.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Button { state.load() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("새로고침")
            }
            ranking
            Divider()
            participation
        }
        .padding(16)
        .frame(width: 360, height: 500)
        .onAppear { state.load() }
    }

    @ViewBuilder
    private var ranking: some View {
        if let message = state.message {
            Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = state.board {
            if result.entries.isEmpty {
                Text(state.period == .week ? "이번 주 기록이 아직 없습니다." : "아직 기록이 없습니다.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(result.entries) { row($0) }
                    }
                }
            }
            if let you = result.you {
                Text("내 순위 \(you.rank)위 · \(result.total)명 중 · 최고 \(you.score)점")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(result.total)명이 참여했습니다.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ entry: Leaderboard.Board.Entry) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? Color(nsColor: NSColor(hex: 0xE0A82E)) : .secondary)
                .frame(width: 28, alignment: .trailing)
            Text(entry.nickname).font(.system(size: 12.5, weight: entry.you ? .semibold : .regular)).lineLimit(1)
            if entry.you { Text("나").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
            Spacer()
            Text("\(entry.score)").font(.system(size: 12.5, weight: .medium).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(entry.you ? 0.14 : 0)))
    }

    private var participation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("순위에 참여", isOn: $board.isOn)
            HStack {
                TextField("닉네임 (2~12자)", text: $board.nickname)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!board.isOn)
                Button("이름 바꾸기") { state.rename() }
                    .disabled(!board.isOn || !Leaderboard.isValid(nickname: board.nickname))
                    .help("이미 올린 기록의 닉네임도 바꿉니다")
            }
            if board.isOn, !Leaderboard.isValid(nickname: board.nickname) {
                Text("한글·영문·숫자로 2~12자를 넣어야 점수를 보냅니다.").font(.caption).foregroundStyle(.orange)
            }
            Text("최근 7일 동안 보낸 점수보다 높으면 무작위 ID, 닉네임, 점수, 코인 수, 플레이 시간, 앱 버전만 보냅니다. 사용량이나 Claude 계정 정보는 보내지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let notice = state.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("내 기록 지우기", role: .destructive) { state.forget() }
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

    func load() {
        board = nil
        message = nil
        let period = period
        Leaderboard.shared.fetch(period) { [weak self] result in
            guard let self, self.period == period else { return }
            switch result {
            case .success(let board): self.board = board
            case .failure(let error): self.message = error.localizedDescription
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

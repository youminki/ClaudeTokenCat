import SwiftUI
import GameCore

/// 러너 고르기 화면 맨 위의 게임 지갑. 오늘의 미션과 꾸미기 상점.
struct GameShopView: View {
    @ObservedObject private var wallet = GameWallet.shared
    private let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

    var body: some View {
        let board = wallet.missions
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("게임 꾸미기").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Label("\(wallet.coins.formatted())", systemImage: "dollarsign.circle.fill")
                        .font(Theme.value)
                        .foregroundStyle(gold)
                        .help("미니게임에서 먹은 코인과 미션 보상")
                }
                Text("오늘의 미션 \(board.doneCount)/\(board.missions.count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(board.missions.enumerated()), id: \.offset) { index, mission in
                    missionRow(mission, progress: board.progress[index], done: board.isDone(index))
                }
                ForEach(Cosmetic.Slot.allCases, id: \.self) { slot in
                    HStack(spacing: 6) {
                        Text(slot.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                        ForEach(Cosmetic.allCases.filter { $0.slot == slot }) { item in itemButton(item) }
                    }
                }
            }
        }
    }

    private func missionRow(_ mission: DailyMissions.Mission, progress: Int, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : mission.icon)
                .foregroundStyle(done ? Theme.positive : Theme.secondary)
                .frame(width: 16)
            Text(mission.title).font(Theme.caption).foregroundStyle(done ? Theme.tertiary : Theme.primary)
            Spacer()
            Text(done ? "완료" : "\(min(progress, mission.target))/\(mission.target)")
                .font(Theme.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("+\(mission.reward)").font(Theme.caption.monospacedDigit())
                .foregroundStyle(done ? Theme.tertiary : gold)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func itemButton(_ item: Cosmetic) -> some View {
        let owned = wallet.owned.contains(item)
        let on = wallet.equipped.contains(item)
        let affordable = owned || wallet.coins >= item.price
        return Button { wallet.choose(item) } label: {
            VStack(spacing: 1) {
                Circle().fill(Color(nsColor: item.color)).frame(width: 8, height: 8)
                Text(item.name).font(.system(size: 10.5, weight: .medium))
                Text(on ? "다는 중" : owned ? "가짐" : "\(item.price)")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(on ? Theme.accent : owned ? Theme.secondary : gold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.7) : Color.clear))
            .opacity(affordable ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
        .help(on ? "누르면 뗍니다" : owned ? "누르면 답니다" : "\(item.price)코인에 사서 답니다")
        .accessibilityLabel("\(slotName(item)) \(item.name)")
    }

    private func slotName(_ item: Cosmetic) -> String { item.slot.title }
}

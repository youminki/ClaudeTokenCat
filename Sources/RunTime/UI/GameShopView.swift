import SwiftUI
import GameCore

/// 러너 고르기 화면 맨 위의 게임 지갑. 오늘의 미션과 상점 (러너, 색, 꼬리, 발먼지, 부딪힘 효과).
struct GameShopView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var wallet = GameWallet.shared
    @StateObject private var state = ShopState()

    private let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

    enum Tab: String, CaseIterable {
        case ability = "능력", theme = "색", trail = "꼬리", dust = "발먼지", crash = "부딪힘"

        var slot: Cosmetic.Slot? {
            switch self {
            case .trail: .trail
            case .dust: .dust
            case .crash: .crash
            default: nil
            }
        }
    }

    var body: some View {
        let board = wallet.missions
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("게임 상점").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Label("\(wallet.coins.formatted())", systemImage: "dollarsign.circle.fill")
                        .font(Theme.value)
                        .foregroundStyle(gold)
                        .help("미니게임에서 먹은 코인과 미션 보상. Claude가 일하는 동안 한 판은 두 배")
                }
                Text("오늘의 미션 \(board.doneCount)/\(board.missions.count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(board.missions.enumerated()), id: \.offset) { index, mission in
                    missionRow(mission, progress: board.progress[index], done: board.isDone(index))
                }
                Picker("", selection: $state.tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .padding(.top, 2)
                if state.tab == .ability {
                    VStack(spacing: 6) { ForEach(Ability.allCases) { abilityRow($0) } }
                } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    switch state.tab {
                    case .theme:
                        ForEach(SpriteTheme.allCases.filter { $0.price != nil }, id: \.self) { themeItem($0) }
                    default:
                        ForEach(Cosmetic.allCases.filter { $0.slot == state.tab.slot }) { cosmeticItem($0) }
                    }
                }
                }
                Text(footnote).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .onChange(of: state.tab) { _ in state.confirming = nil }
    }

    private var footnote: String {
        switch state.tab {
        case .ability: "능력은 미니게임에서만 쓰고 다음 판부터 적용됩니다. 순위 점수 계산은 같습니다."
        case .theme: "산 색은 색상 메뉴에 생기고 메뉴바 러너에도 칠해집니다."
        default: "게임 화면에만 보이고 점수와 판정은 같습니다. 다시 누르면 뗍니다."
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

    // MARK: 물건

    /// 코인이 줄었으면(실제로 샀으면) 사는 소리를 낸다. 달기·떼기만 했으면 조용하다.
    private func buying(_ action: () -> Void) {
        let before = wallet.coins
        action()
        if wallet.coins < before { GameSound.shared.play(.purchase) }
    }

    /// 능력 한 줄: 단계, 켜고 끄기, 다음 단계 사기 (두 번 눌러 산다).
    private func abilityRow(_ ability: Ability) -> some View {
        let level = wallet.level(ability)
        let next = wallet.nextPrice(ability)
        let key = "ability:\(ability.rawValue)"
        let asking = state.confirming == key
        return HStack(spacing: 8) {
            Image(systemName: ability.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(level > 0 ? Theme.accent : Theme.tertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ability.name).font(.system(size: 11.5, weight: .semibold))
                    HStack(spacing: 2) {
                        ForEach(0..<ability.maxLevel, id: \.self) { i in
                            Circle().fill(i < level ? gold : Color.white.opacity(0.15)).frame(width: 5, height: 5)
                        }
                    }
                }
                Text(ability.detail(level: max(level, 1))).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if level > 0 {
                Toggle("", isOn: Binding(get: { wallet.isOn(ability) }, set: { _ in wallet.toggle(ability) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .help("이번 판에 쓸지")
            }
            if let next {
                let affordable = wallet.coins >= next
                Button {
                    if asking {
                        state.confirming = nil
                        buying { wallet.upgrade(ability) }
                    } else if affordable {
                        state.confirming = key
                    }
                } label: {
                    Text(asking ? "\(next)에 사기?" : level == 0 ? "\(next)" : "+1단계 \(next)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(asking ? Theme.warning.opacity(0.25) : Color.white.opacity(0.08)))
                        .foregroundStyle(asking ? Theme.warning : affordable ? gold : Theme.tertiary)
                }
                .buttonStyle(.plain)
                .help(affordable ? "두 번 누르면 삽니다" : "코인 \(next - wallet.coins)개가 더 필요해요")
            } else {
                Text("최대").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.positive)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func themeItem(_ theme: SpriteTheme) -> some View {
        let owned = wallet.owns(theme)
        return item(key: "theme:\(theme.rawValue)", name: theme.displayName, price: theme.price ?? 0,
                    owned: owned, on: settings.spriteTheme == theme, ownedLabel: "칠하기") {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                CharacterCanvas(character: settings.character, theme: theme, date: context.date)
            }
            .frame(height: 30)
        } action: {
            if owned || wallet.buy(theme) { settings.spriteTheme = theme }
        }
    }

    private func cosmeticItem(_ cosmetic: Cosmetic) -> some View {
        let owned = wallet.owned.contains(cosmetic)
        return item(key: cosmetic.rawValue, name: cosmetic.name, price: cosmetic.price, owned: owned,
                    on: wallet.equipped.contains(cosmetic), ownedLabel: "달기") {
            Image(systemName: cosmetic.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: cosmetic.color))
                .frame(height: 30)
        } action: {
            wallet.choose(cosmetic)
        }
    }

    /// 공통 칸. 안 산 것은 처음 누르면 "사기?"로 바뀌고, 한 번 더 누르면 산다.
    private func item<Preview: View>(key: String, name: String, price: Int, owned: Bool, on: Bool, ownedLabel: String,
                                     @ViewBuilder preview: () -> Preview, action: @escaping () -> Void) -> some View {
        let affordable = owned || wallet.coins >= price
        let asking = state.confirming == key
        let status: String
        let statusColor: Color
        if on {
            status = "쓰는 중"; statusColor = Theme.accent
        } else if owned {
            status = ownedLabel; statusColor = Theme.secondary
        } else if asking {
            status = "\(price)에 사기?"; statusColor = Theme.warning
        } else {
            status = "\(price)"; statusColor = affordable ? gold : Theme.tertiary
        }
        return Button {
            if owned || asking {
                state.confirming = nil
                buying(action)
            } else if affordable {
                state.confirming = key
            }
        } label: {
            VStack(spacing: 2) {
                preview()
                Text(name).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 2) {
                    if !owned && !asking { Image(systemName: affordable ? "dollarsign.circle.fill" : "lock.fill") }
                    Text(status)
                }
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Theme.accent.opacity(0.18) : asking ? Theme.warning.opacity(0.15) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.7) : asking ? Theme.warning.opacity(0.7) : Color.clear))
            .opacity(affordable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .help(affordable ? (owned ? name : "\(price)코인. 두 번 누르면 삽니다") : "코인 \(price - wallet.coins)개가 더 필요해요")
        .accessibilityLabel("\(name), \(status)")
    }
}

extension Cosmetic {
    var icon: String {
        switch self {
        case .sparkleTrail: "sparkles"
        case .cometTrail: "wind"
        case .rainbowTrail: "rainbow"
        case .fireTrail: "flame.fill"
        case .noteTrail: "music.note"
        case .heartTrail: "heart.fill"
        case .heartDust: "aqi.low"
        case .goldDust: "aqi.medium"
        case .starDust: "snowflake"
        case .rainbowDust: "circle.hexagongrid.fill"
        case .fireworksCrash: "fireworks"
        case .heartCrash: "heart.circle.fill"
        case .coinCrash: "dollarsign.circle.fill"
        }
    }
}

/// 상점 탭과 사기 직전인 물건. 처음 누르면 confirming에 두고, 한 번 더 누르면 산다
/// (팝오버에서는 확인 창을 띄우면 팝오버가 닫혀서).
final class ShopState: ObservableObject {
    @Published var tab: GameShopView.Tab = .ability
    @Published var confirming: String?
}

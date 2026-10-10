import SwiftUI
import GameCore

/// 게임 상점. 위에서 갈래(능력, 동료, 꼬리, 발먼지, 부딪힘, 색)를 고르고, 물건마다 게임에서 보일 모습을 움직여 보여 준다.
struct GameShopView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var wallet = GameWallet.shared
    @StateObject private var state: ShopState

    init(settings: AppSettings, tab: Tab = .buddy) {
        self.settings = settings
        _state = StateObject(wrappedValue: ShopState(tab: tab))
    }

    static let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

    enum Tab: String, CaseIterable {
        case ability = "능력", buddy = "동료", trail = "꼬리", dust = "발먼지", crash = "부딪힘", theme = "색"

        var slot: Cosmetic.Slot? {
            switch self {
            case .buddy: .buddy
            case .trail: .trail
            case .dust: .dust
            case .crash: .crash
            default: nil
            }
        }

        var icon: String {
            switch self {
            case .ability: "bolt.shield.fill"
            case .buddy: "person.2.fill"
            case .trail: "wind"
            case .dust: "aqi.medium"
            case .crash: "burst.fill"
            case .theme: "paintpalette.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabs
            switch state.tab {
            case .ability:
                VStack(spacing: 6) { ForEach(Ability.allCases) { abilityRow($0) } }
            case .theme:
                grid(SpriteTheme.allCases.filter { $0.price != nil }.map(ShopItem.theme))
            default:
                grid(Cosmetic.allCases.filter { $0.slot == state.tab.slot }.sorted { $0.price < $1.price }.map(ShopItem.cosmetic))
            }
            Text(footnote).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: state.tab) { _ in state.confirming = nil }
    }

    /// 갈래 고르기. 여섯 개라 아이콘과 짧은 이름을 두 줄로 둔다.
    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let on = state.tab == tab
                Button { state.tab = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(on ? Theme.primary : Theme.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? Color.white.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
    }

    private var footnote: String {
        switch state.tab {
        case .ability: "능력은 미니게임에서만 쓰고 다음 판부터 적용됩니다. 순위 점수 계산은 같습니다."
        case .theme: "산 색은 색상 메뉴에 생기고 메뉴바 러너에도 칠해집니다."
        case .buddy: "동료는 게임에서 러너 뒤를 따라 달립니다. 판정과 점수는 같습니다."
        default: "게임 화면에만 보이고 점수와 판정은 같습니다. 다시 누르면 뗍니다."
        }
    }

    // MARK: 물건 칸

    enum ShopItem: Hashable {
        case cosmetic(Cosmetic)
        case theme(SpriteTheme)
    }

    private func grid(_ items: [ShopItem]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .cosmetic(let cosmetic): cosmeticItem(cosmetic)
                case .theme(let theme): themeItem(theme)
                }
            }
        }
    }

    /// 코인이 줄었으면(실제로 샀으면) 사는 소리를 낸다. 달기·떼기만 했으면 조용하다.
    private func buying(_ action: () -> Void) {
        let before = wallet.coins
        action()
        if wallet.coins < before { GameSound.shared.play(.purchase) }
    }

    private func themeItem(_ theme: SpriteTheme) -> some View {
        let owned = wallet.owns(theme)
        return card(key: "theme:\(theme.rawValue)", name: theme.displayName, price: theme.price ?? 0,
                    owned: owned, on: settings.spriteTheme == theme, ownedLabel: "칠하기") {
            ItemPreview(kind: .theme(theme), character: settings.character)
        } action: {
            if owned || wallet.buy(theme) { settings.spriteTheme = theme }
        }
    }

    private func cosmeticItem(_ cosmetic: Cosmetic) -> some View {
        let owned = wallet.owned.contains(cosmetic)
        return card(key: cosmetic.rawValue, name: cosmetic.name, price: cosmetic.price, owned: owned,
                    on: wallet.equipped.contains(cosmetic), ownedLabel: cosmetic.slot == .buddy ? "데려가기" : "달기") {
            ItemPreview(kind: .cosmetic(cosmetic), character: settings.character)
        } action: {
            wallet.choose(cosmetic)
        }
    }

    /// 공통 칸. 안 산 것은 처음 누르면 "사기?"로 바뀌고, 한 번 더 누르면 산다
    /// (팝오버에서 확인 창을 띄우면 팝오버가 닫혀서).
    private func card<Preview: View>(key: String, name: String, price: Int, owned: Bool, on: Bool, ownedLabel: String,
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
            status = price.formatted(); statusColor = affordable ? Self.gold : Theme.tertiary
        }
        return Button {
            if owned || asking {
                state.confirming = nil
                buying(action)
            } else if affordable {
                state.confirming = key
            }
        } label: {
            VStack(spacing: 6) {
                preview()
                    .frame(height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if !owned {
                            Image(systemName: affordable ? "bag.fill" : "lock.fill")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                                .padding(4)
                        }
                    }
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(1)
                    Spacer(minLength: 2)
                    HStack(spacing: 2) {
                        if !owned && !asking { Image(systemName: "dollarsign.circle.fill") }
                        Text(status)
                    }
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on ? Theme.accent.opacity(0.16) : asking ? Theme.warning.opacity(0.14) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.75) : asking ? Theme.warning.opacity(0.7) : Theme.hairline))
            .opacity(affordable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .help(affordable ? (owned ? name : "\(price)코인. 두 번 누르면 삽니다") : "코인 \(price - wallet.coins)개가 더 필요해요")
        .accessibilityLabel("\(name), \(status)")
    }

    // MARK: 능력

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
                            Circle().fill(i < level ? Self.gold : Color.white.opacity(0.15)).frame(width: 5, height: 5)
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
                    .accessibilityLabel("\(ability.name) 쓰기")
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
                        .foregroundStyle(asking ? Theme.warning : affordable ? Self.gold : Theme.tertiary)
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
}

/// 상점 갈래와 사기 직전인 물건. `@State`를 못 쓰는 이유는 HoverFlag 참고.
final class ShopState: ObservableObject {
    @Published var tab: GameShopView.Tab
    @Published var confirming: String?

    init(tab: GameShopView.Tab) { self.tab = tab }
}

// MARK: - 미리보기

/// 상점 칸 위의 작은 무대. 게임과 같은 그림 함수로 그 물건이 게임에서 보일 모습을 계속 돌려 보여 준다.
struct ItemPreview: View {
    enum Kind {
        case cosmetic(Cosmetic)
        case theme(SpriteTheme)
    }

    let kind: Kind
    let character: RunnerCharacter

    var body: some View {
        // 칸이 여럿이라 1초 20장으로 그린다
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                canvas.withCGContext { cg in draw(cg, size: size, time: time) }
            }
        }
        .accessibilityHidden(true)
    }

    func draw(_ cg: CGContext, size: CGSize, time: Double) {
        let ground = size.height - 9
        // 밤하늘 바탕과 땅
        let colors = [NSColor(hex: 0x1B2140).cgColor, NSColor(hex: 0x33406E).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: ground), options: [.drawsAfterEndLocation])
        }
        for i in 0..<9 {
            let twinkle = 0.3 + 0.5 * abs(sin(time * 1.3 + Double(i)))
            cg.setFillColor(NSColor.white.withAlphaComponent(twinkle).cgColor)
            cg.fillEllipse(in: CGRect(x: RunnerStageHash.value(i, 41) * size.width, y: RunnerStageHash.value(i, 42) * (ground - 16) + 3,
                                      width: 1.4, height: 1.4))
        }
        cg.setFillColor(NSColor(hex: 0x1A1F3A).cgColor)
        cg.fill(CGRect(x: 0, y: ground, width: size.width, height: size.height - ground))
        cg.setFillColor(NSColor(hex: 0x6C7BC4).withAlphaComponent(0.8).cgColor)
        cg.fill(CGRect(x: 0, y: ground - 0.5, width: size.width, height: 1.5))
        // 땅 무늬가 흘러 달리는 느낌을 준다
        cg.setFillColor(NSColor(hex: 0x6C7BC4).withAlphaComponent(0.3).cgColor)
        let offset = CGFloat((time * 60).truncatingRemainder(dividingBy: 18))
        var x = -offset
        while x < size.width { cg.fill(CGRect(x: x, y: ground + 4, width: 7, height: 1.5)); x += 18 }

        let runnerX = size.width * 0.66
        switch kind {
        case .theme(let theme):
            drawRunner(cg, centerX: size.width / 2, ground: ground, height: 50, theme: theme, time: time)
        case .cosmetic(let item):
            switch item.slot {
            case .buddy:
                // 동료만 크게, 두 배로 키워 도트를 또렷하게
                let hop = CGFloat(max(0, sin(time * 5))) * 3
                GameFX.drawBuddy(item, feet: CGPoint(x: size.width / 2, y: ground - hop), step: time * 6, scale: 2, cg)
            case .trail:
                let base = ground - 18
                let head = CGPoint(x: runnerX - 8, y: base)
                let points = (0..<22).map { i -> CGPoint in
                    let back = CGFloat(21 - i)
                    return CGPoint(x: head.x - back * 4.2, y: base + CGFloat(sin(time * 4 - Double(i) * 0.33)) * 5 * back / 21)
                }
                GameFX.drawTrail(item, points: points, time: time, cg)
                drawRunner(cg, centerX: runnerX, ground: ground, height: 40, theme: .auto, time: time)
            case .dust:
                // 0.18초마다 디딘 발밑에서 먼지가 인다
                let feet = CGPoint(x: runnerX - 6, y: ground)
                let spray = GameFX.dust(item, landing: false)
                // 게임에서는 작은 먼지라 칸에서는 두 배로 키워 모양이 보이게 한다
                zoomed(cg, around: feet, by: 2) {
                    for k in 0..<4 {
                        let age = CGFloat((time + Double(k) * 0.18).truncatingRemainder(dividingBy: 0.72))
                        GameFX.drawSpray(spray, from: feet, age: age, time: time, cg)
                    }
                }
                drawRunner(cg, centerX: runnerX, ground: ground, height: 40, theme: .auto, time: time)
            case .crash:
                // 장애물에 부딪혀 1.6초마다 터진다
                let center = CGPoint(x: size.width / 2, y: ground - 18)
                if let spikes = GameSprite.spikes.frame(at: time) {
                    GameAssets.draw(spikes, in: CGRect(x: center.x - 18 + 14, y: ground - 36 + 4, width: 36, height: 36), cg)
                }
                drawRunner(cg, centerX: center.x - 18, ground: ground, height: 34, theme: .auto, time: time, sitting: true)
                let age = CGFloat(time.truncatingRemainder(dividingBy: 1.6))
                zoomed(cg, around: center, by: 1.4) {
                    for part in GameFX.crash(item) {
                        GameFX.drawSpray(part.spray, from: CGPoint(x: center.x + part.offset.x * 0.6, y: center.y - part.offset.y * 0.6),
                                         age: age, time: time, cg)
                    }
                }
            }
        }
    }

    private func zoomed(_ cg: CGContext, around point: CGPoint, by scale: CGFloat, _ draw: () -> Void) {
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y)
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -point.x, y: -point.y)
        draw()
        cg.restoreGState()
    }

    private func drawRunner(_ cg: CGContext, centerX: CGFloat, ground: CGFloat, height: CGFloat, theme: SpriteTheme,
                            time: Double, sitting: Bool = false) {
        let width = height * Stage.size.width / Stage.size.height
        let phase = CGFloat(time.truncatingRemainder(dividingBy: 72) / 0.72)
        let frame = MotionFrame(pose: CharacterPose(activity: sitting ? .sit : .run, phase: phase))
        cg.saveGState()
        // 캐릭터 무대의 바닥 줄을 땅에 맞춘다
        let scale = height / Stage.size.height
        cg.translateBy(x: centerX - width / 2, y: ground - Stage.ground * scale)
        CharacterCanvas.draw(cg, size: CGSize(width: width, height: height), rig: character.rig, frame: frame,
                             theme: character.theme(theme), themePhase: CGFloat(time / 6))
        cg.restoreGState()
    }
}

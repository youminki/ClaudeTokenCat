import SwiftUI
import GameCore

/// 퀘스트: 오늘의 미션, 이번 주 도전, 업적. 판이 끝날 때 채운 만큼 코인이 바로 들어온다.
struct QuestView: View {
    @ObservedObject private var wallet = GameWallet.shared

    var body: some View {
        let daily = wallet.missions
        let weekly = wallet.weekly
        VStack(alignment: .leading, spacing: 10) {
            section("오늘의 미션", trailing: "\(daily.doneCount)/\(daily.missions.count) · \(Self.untilTomorrow())") {
                ForEach(Array(daily.missions.enumerated()), id: \.offset) { index, mission in
                    row(icon: mission.icon, title: mission.title(weekly: false), progress: daily.progress[index],
                        target: mission.target, reward: mission.reward, done: daily.isDone(index))
                }
            }
            section("이번 주 도전", trailing: "\(weekly.doneCount)/\(weekly.missions.count) · \(Self.untilNextWeek())") {
                ForEach(Array(weekly.missions.enumerated()), id: \.offset) { index, mission in
                    row(icon: mission.icon, title: mission.title(weekly: false), progress: weekly.progress[index],
                        target: mission.target, reward: mission.reward, done: weekly.isDone(index))
                }
            }
            let book = wallet.achievements
            let done = Achievements.Kind.allCases.reduce(0) { $0 + book.levels($1) }
            let total = Achievements.Kind.allCases.reduce(0) { $0 + Achievements.maxLevel($1) }
            section("업적", trailing: "\(done)/\(total)") {
                ForEach(Achievements.Kind.allCases, id: \.self) { kind in
                    achievementRow(kind, book: book)
                }
            }
            Text("판이 끝나면 채운 퀘스트의 코인이 바로 들어옵니다. Claude가 일하는 동안 한 판은 먹은 코인이 두 배입니다.")
                .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, trailing: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                    Spacer()
                    Text(trailing).font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
                content()
            }
        }
    }

    private func row(icon: String, title: String, progress: Int, target: Int, reward: Int, done: Bool) -> some View {
        let value = min(progress, target)
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(done ? Theme.positive : Theme.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(Theme.caption).foregroundStyle(done ? Theme.tertiary : Theme.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(done ? "완료" : "\(value.formatted())/\(target.formatted())")
                        .font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
                ProgressTrack(fraction: Double(value) / Double(max(target, 1)), done: done)
            }
            rewardChip(reward, done: done)
        }
        .accessibilityElement(children: .combine)
    }

    private func achievementRow(_ kind: Achievements.Kind, book: Achievements) -> some View {
        let level = book.levels(kind)
        let max = Achievements.maxLevel(kind)
        let next = book.next(kind)
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(level > 0 ? GameShopView.gold.opacity(0.18) : Color.white.opacity(0.06))
                Image(systemName: kind.icon).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(level > 0 ? GameShopView.gold : Theme.tertiary)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(kind.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.primary)
                    // 받은 단계는 금색 별
                    HStack(spacing: 1.5) {
                        ForEach(0..<max, id: \.self) { i in
                            Image(systemName: "star.fill").font(.system(size: 6.5))
                                .foregroundStyle(i < level ? GameShopView.gold : Color.white.opacity(0.15))
                        }
                    }
                    Spacer(minLength: 4)
                    if let next {
                        Text("\(min(book.value(kind), next.target).formatted())/\(next.target.formatted())")
                            .font(Theme.caption.monospacedDigit()).foregroundStyle(Theme.tertiary)
                    } else {
                        Text("모두 달성").font(Theme.caption).foregroundStyle(Theme.positive)
                    }
                }
                if let next {
                    Text(kind.goal(next.target)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    ProgressTrack(fraction: Double(book.value(kind)) / Double(Swift.max(next.target, 1)), done: false)
                }
            }
            if let next { rewardChip(next.reward, done: false) } else { rewardChip(nil, done: true) }
        }
        .accessibilityElement(children: .combine)
    }

    private func rewardChip(_ reward: Int?, done: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: done ? "checkmark" : "dollarsign.circle.fill").font(.system(size: 9, weight: .bold))
            if let reward { Text("+\(reward)") }
        }
        .font(.system(size: 10, weight: .semibold).monospacedDigit())
        .foregroundStyle(done ? Theme.tertiary : GameShopView.gold)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(done ? Color.white.opacity(0.05) : GameShopView.gold.opacity(0.14)))
        .frame(minWidth: 46, alignment: .trailing)
    }

    /// "5시간 뒤 새 미션"
    static func untilTomorrow(now: Date = Date()) -> String {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return "" }
        return "\(Format.duration(tomorrow.timeIntervalSince(now))) 뒤 바뀜"
    }

    /// 다음 월요일 0시까지 (ISO 주).
    static func untilNextWeek(now: Date = Date()) -> String {
        let calendar = Calendar(identifier: .iso8601)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return "" }
        return "\(Format.duration(week.end.timeIntervalSince(now))) 뒤 바뀜"
    }
}

/// 얇은 진행 막대.
private struct ProgressTrack: View {
    let fraction: Double
    let done: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(done ? Theme.positive : GameShopView.gold)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}

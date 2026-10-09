import GameCore
import SwiftUI

/// 점수판과 시작·끝 화면 글자.
extension GameSession {
    // MARK: 점수판

    /// 무대 위 글자. 그리기 컨텍스트가 바로 그리도록 위치와 함께 넘긴다.
    struct Label {
        let text: Text
        let position: CGPoint
        var anchor: UnitPoint = .center
    }

    struct Panel {
        let rect: CGRect
    }

    func overlay(size: CGSize) -> (panels: [Panel], labels: [Label]) {
        var labels: [Label] = []
        var panels: [Panel] = []
        // 100점마다 점수가 잠깐 커진다
        let digits = GameFont.pixel(18 * (1 + 0.3 * milestoneGlow * milestoneGlow))
        let small = GameFont.pixel(12)
        let gold = Color(nsColor: NSColor(hex: 0xFFD45E))

        if game.phase != .ready {
            let glow = milestoneGlow > 0 && Int(milestoneGlow * 10) % 2 == 0
            labels.append(Label(text: Text(String(format: "%05d", game.score)).font(digits)
                                    .foregroundColor(glow ? gold : .white),
                                position: CGPoint(12, 10), anchor: .topLeading))
            // 끝난 화면은 패널이 최고 점수를 보여 주고, 왼쪽 위 글자는 패널 가장자리와 겹친다
            if game.phase == .playing {
                labels.append(Label(text: Text("최고 \(max(game.best, game.score))").font(small)
                                        .foregroundColor(.white.opacity(0.75)),
                                    position: CGPoint(12, 29), anchor: .topLeading))
            }
            if game.phase == .playing, !game.abilities.isEmpty {
                var parts: [String] = []
                if game.abilities.shields > 0 { parts.append("보호막 \(game.shieldsLeft)") }
                if game.abilities.airJumps > 0 { parts.append("이단 점프") }
                if game.abilities.magnet > 0 { parts.append("자석") }
                if game.abilities.glide { parts.append("글라이드") }
                labels.append(Label(text: Text(parts.joined(separator: " · ")).font(small)
                                        .foregroundColor(Color(nsColor: NSColor(hex: 0x8FD3FF)).opacity(0.9)),
                                    position: CGPoint(12, 57), anchor: .topLeading))
            }
            if game.phase == .playing, game.coinsTaken > 0 || boosted {
                let double = boosted ? "  ×2 Claude 작업 중" : ""
                labels.append(Label(text: Text("코인 \(game.coinsTaken)\(double)").font(small).foregroundColor(gold.opacity(0.9)),
                                    position: CGPoint(12, 43), anchor: .topLeading))
            }
        }
        for popup in popups {
            labels.append(Label(text: Text(popup.text).font(GameFont.pixel(12))
                                    .foregroundColor(gold.opacity(Double(min(1, popup.life * 2)))),
                                position: CGPoint(popup.position.x, (size.height - 15) - popup.position.y - 14)))
        }
        if game.phase == .playing, let next = tracker.next {
            // 오른쪽 위 단추와 겹치지 않게 긴 닉네임은 자른다
            let name = next.name.count > 6 ? next.name.prefix(6) + "…" : Substring(next.name)
            labels.append(Label(text: Text("목표 \(String(name)) \(next.score) (-\(max(0, next.score + 1 - game.score)))")
                                    .font(small).foregroundColor(.white.opacity(0.85)),
                                position: CGPoint(size.width / 2, 12)))
            if let x = flagX(), x > 0, x < size.width {
                labels.append(Label(text: Text(next.name).font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.white),
                                    position: CGPoint(x + 8, size.height - 15 - 56)))
            }
        }
        if game.phase == .playing, let lead = raceLead, let raceTarget {
            let who = Self.shortName(raceTarget.name)
            let text = lead > 0 ? "\(who) 추월! +\(lead)" : "\(who) \(raceTarget.score) (-\(1 - lead))"
            labels.append(Label(text: Text(text).font(small).foregroundColor(lead > 0 ? gold : .white.opacity(0.85)),
                                position: CGPoint(size.width / 2, 12)))
        }
        if let overtaken, game.phase == .playing {
            labels.append(Label(text: Text("\(overtaken.name) 추월!").font(GameFont.pixel(18))
                                    .foregroundColor(gold.opacity(Double(min(1, overtaken.life * 2)))),
                                position: CGPoint(size.width / 2, 34)))
        }
        if let zoneBanner, game.phase == .playing {
            labels.append(Label(text: Text(zoneBanner.text).font(GameFont.pixel(18))
                                    .foregroundColor(.white.opacity(Double(min(1, zoneBanner.life * 2)))),
                                position: CGPoint(size.width / 2, 52)))
        }
        if let notice {
            labels.append(Label(text: Text(notice.text).font(GameFont.pixel(12))
                                    .foregroundColor(Color(nsColor: NSColor(hex: 0x8FD3FF)).opacity(Double(min(1, notice.life * 2)))),
                                position: CGPoint(size.width / 2, game.phase == .playing ? 70 : 14)))
        }
        if recordBanner > 0, game.phase == .playing {
            labels.append(Label(text: Text("신기록!").font(GameFont.pixel(18))
                                    .foregroundColor(gold.opacity(Double(min(1, recordBanner * 3)))),
                                position: CGPoint(size.width / 2, overtaken == nil ? 34 : 52)))
        }

        let center = CGPoint(size.width / 2, size.height / 2 - 12)
        // 고스트 단축키. 겨룰 고스트 한 줄, 코드 복사·붙여넣기 한 줄
        var races: [String] = []
        if let savedGhost { races.append("G 내 고스트 \(savedGhost.score)") }
        if let top = TopGhost.all.record {
            races.append("1 \(top.rank.map { "\($0)위" } ?? "1위") \(Self.shortName(top.name))")
        }
        if let week = weekGhost {
            races.append("2 주간 \(Self.shortName(week.name))")
        }
        let ghostLines = races.isEmpty ? [] : [races.joined(separator: " · ")]
        let ghostColors = ghostLines.map { _ in gold.opacity(0.9) }
        let ghostExtra = CGFloat(ghostLines.count) * 14
        func addGhostLines(from y: CGFloat) {
            for (i, line) in ghostLines.enumerated() {
                labels.append(Label(text: Text(line).font(small).foregroundColor(ghostColors[i]),
                                    position: CGPoint(center.x, y + CGFloat(i) * 14)))
            }
        }
        switch game.phase {
        case .ready where entrance >= 1:
            panels.append(Panel(rect: CGRect(x: center.x - 125, y: center.y - 34, width: 250, height: 62 + ghostExtra)))
            labels.append(Label(text: Text("토큰 러너").font(GameFont.pixel(18))
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y - 18)))
            labels.append(Label(text: Text("스페이스·클릭으로 시작").font(GameFont.pixel(12))
                                    .foregroundColor(.white.opacity(0.9)), position: CGPoint(center.x, center.y)))
            let best = game.best > 0 ? "최고 \(game.best)  ·  " : ""
            labels.append(Label(text: Text("\(best)↑ 길게 높이 · ↓ 숙이기 · ←→ 이동").font(small)
                                    .foregroundColor(.white.opacity(0.65)), position: CGPoint(center.x, center.y + 16)))
            addGhostLines(from: center.y + 30)
        case .over:
            // 겨루는 판은 순위 대신 고스트와의 차이를 보여 준다
            let raceLine = raceLead.map { lead in
                lead > 0 ? "\(lead)점 앞섬 · 기록에는 남지 않음" : "\(-lead + 1)점 모자람"
            }
            let middle = raceLine ?? rankLine
            let won = (raceLead ?? 0) > 0
            let who = raceTarget?.name.map { "\(Self.shortName($0)) 고스트" } ?? "고스트"
            let title = isRace ? (won ? "\(who)를 이겼다!" : "\(who)에게 졌다")
                : game.isNewRecord ? "신기록!" : "앗, 부딪혔다"
            // 픽셀 글꼴은 줄 높이가 커서 줄 사이를 넉넉히 둔다
            labels.append(Label(text: Text(title).font(GameFont.pixel(18))
                                    .foregroundColor(won || (!isRace && game.isNewRecord) ? gold : .white),
                                position: CGPoint(center.x, center.y - 22)))
            labels.append(Label(text: Text("\(game.score)점").font(GameFont.pixel(24))
                                    .foregroundColor(.white), position: CGPoint(center.x, center.y + 3)))
            var y = center.y + 25
            if let middle {
                labels.append(Label(text: Text(middle).font(small).foregroundColor(gold), position: CGPoint(center.x, y)))
                y += 14
            }
            labels.append(Label(text: Text("최고 \(game.best) · 스페이스로 새 판").font(small)
                                    .foregroundColor(.white.opacity(0.7)), position: CGPoint(center.x, y)))
            addGhostLines(from: y + 14)
            let bottom = y + ghostExtra + 10
            panels.append(Panel(rect: CGRect(x: center.x - 125, y: center.y - 36, width: 250, height: bottom - (center.y - 36))))
        default:
            break
        }
        return (panels, labels)
    }
}

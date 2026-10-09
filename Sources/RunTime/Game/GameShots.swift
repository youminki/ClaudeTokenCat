import AppKit
import GameCore
import SwiftUI

/// 게임 화면 점검 (`--game-shots <폴더> [러너 id]`). 무대와 같은 코드로 자동 플레이를 돌리며
/// 시작 화면, 달리는 장면 몇 장, 부딪힌 화면을 PNG로 남긴다. 팝오버를 열어 직접 해 보지 않고 모습을 확인할 때 쓴다.
enum GameShots {
    @MainActor
    static func run(to directory: URL, character: RunnerCharacter) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = StageModel()
        let size = CGSize(width: 344, height: RunnerStage.height)
        var date = Date()
        let frame = 1.0 / 60
        model.startGame(character: character, rehearsal: true)
        guard let session = model.game else { return }
        let game = session.game
        let pilot = Autopilot(game: game)
        // 순위 서버 없이 라이벌 목표·깃발·추월 배너가 보이게 가짜 두 명을 둔다
        session.rivalSource = { [Rival(name: "토큰고양이", score: 160), Rival(name: "bob", score: 430)] }

        func step(_ seconds: Double, autoplay: Bool) {
            for _ in 0..<Int(seconds / frame) {
                if autoplay { pilot.step() }
                date = date.addingTimeInterval(frame)
                session.update(date: date)
            }
        }

        func shot(_ name: String) throws {
            let view = Canvas { context, size in
                context.withCGContext { cg in
                    model.draw(cg, size: size, date: date, display: .normal(.running), character: character,
                               theme: character.theme(.natural))
                }
                if let game = model.game { RunnerStage.drawOverlay(game.overlay(size: size), in: &context) }
            }
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        }

        step(0.2, autoplay: false)
        try shot("0-entrance")
        step(0.6, autoplay: false)
        try shot("1-ready")
        session.press()
        session.release()
        for k in 1...12 {
            step(3, autoplay: true)
            try shot("2-play-\(k)")
            if game.phase == .over { break }
        }
        // →를 눌러 앞으로 나간 모습. 자동 플레이는 앞뒤 이동을 셈하지 않아 마지막에 찍는다
        if game.phase == .playing {
            game.setMove(forward: true)
            step(0.6, autoplay: true)
            try shot("2-play-forward")
        }
        // 손을 놓고 부딪히게 둔다
        while game.phase == .playing { step(0.25, autoplay: false) }
        try shot("3-crash")
        step(0.6, autoplay: false)
        try shot("4-over")

        // 방금 판을 고스트로 두고 겨룬다. 같은 자동 플레이에 앞으로 조금 나가 고스트와 겹치지 않게 한다
        session.savedGhost = GhostRecord(seed: String(game.seed), score: game.score, layout: GhostStore.layout(of: game),
                                         inputs: game.inputLog)
        try shot("5-over-ghost")
        session.startRace()
        game.setMove(forward: true)
        step(0.4, autoplay: true)
        game.setMove(forward: false)
        step(2.6, autoplay: true)
        try shot("6-race")
        while game.phase == .playing { step(0.25, autoplay: false) }
        step(0.6, autoplay: false)
        try shot("7-race-over")
        print("score \(game.score), coins \(game.coinsTaken), \(String(format: "%.1f", game.elapsed))s, speed \(Int(game.speed))")
    }
}

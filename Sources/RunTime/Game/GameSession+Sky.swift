import AppKit

/// 판 점수에 따라 바뀌는 하늘 구간.
extension GameSession {
    // MARK: 하늘 구간

    static let zoneNames = ["새벽", "낮", "노을", "밤", "우주"]
    static let zoneHours = [6, 12, 18, 22]
    /// 우주에 닿으면 더 바뀌지 않는다.
    static let zoneScore = 500

    static func zone(hour: Int) -> Int {
        switch hour {
        case 5..<8: 0
        case 8..<17: 1
        case 17..<20: 2
        default: 3
        }
    }

    static func sky(zone: Int) -> Sky {
        zone >= zoneHours.count ? Sky.at(hour: 0, space: true) : Sky.at(hour: zoneHours[zone], space: false)
    }

    /// 지금 그릴 하늘. 지금 시각의 하늘에서 시작해 점수가 오를수록 다음 하늘로 간다.
    func sky(hour: Int) -> Sky {
        let start = Self.zone(hour: hour)
        let target = game.phase == .ready ? start : min(start + game.score / Self.zoneScore, Self.zoneNames.count - 1)
        if skyTo == nil {
            skyFrom = target
            skyTo = target
        } else if target != skyTo {
            skyFrom = skyTo ?? target
            skyTo = target
            skyBlend = 0
            if game.phase == .playing {
                zoneBanner = ("\(Self.zoneNames[target]) 구간", 2)
                play(.record)
            }
        }
        let from = Self.sky(zone: skyFrom), to = Self.sky(zone: skyTo ?? target)
        let t = skyBlend * skyBlend * (3 - 2 * skyBlend)
        return t >= 1 ? to : from.mixed(with: to, t)
    }
}

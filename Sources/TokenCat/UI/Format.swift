import Foundation

enum Format {
    /// 1_240_000 → "1.24M", 532_100 → "532K"
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.2fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    static func percent(_ v: Double) -> String {
        String(format: "%.1f%%", v)
    }

    /// 72 → "1시간 12분", 3 → "3분"
    static func minutes(_ total: Int) -> String {
        total >= 60 ? "\(total / 60)시간 \(total % 60)분" : "\(total)분"
    }

    /// 남은 시간. 하루가 넘으면 일·시간, 아니면 시간·분.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
        return minutes(total / 60)
    }

    static func resetCountdown(until end: Date, now: Date = Date()) -> String {
        "\(duration(end.timeIntervalSince(now))) 후 리셋"
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["일", "월", "화", "수", "목", "금", "토"]
        return (1...7).contains(weekday) ? "\(names[weekday - 1])요일" : "?"
    }

    /// "목요일 13:40"
    static func weekdayTime(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return "\(weekdayName(weekday)) \(timeFormatter.string(from: date))"
    }

    static func hour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    static func modelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("fable") { return "Fable" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

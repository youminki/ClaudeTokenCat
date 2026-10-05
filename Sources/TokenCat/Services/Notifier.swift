import Foundation
import UserNotifications

/// macOS 알림 (§F4). UNUserNotificationCenter는 번들 앱에서만 동작 —
/// `swift run` 개발 실행(번들 ID 없음)에서는 조용히 비활성화된다.
final class Notifier {

    static let shared = Notifier()

    /// 번들 앱(.app)으로 실행 중일 때만 사용 가능.
    let available = Bundle.main.bundleIdentifier != nil

    private var authorized = false

    private init() {}

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func send(title: String, body: String) {
        guard available else {
            NSLog("[TokenCat] (알림 비활성 — 번들 앱 아님) %@ %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

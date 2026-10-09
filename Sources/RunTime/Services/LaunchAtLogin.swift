import Foundation
import ServiceManagement

/// 로그인 시 자동 시작 (SMAppService, macOS 13+). 번들 앱에서만 동작.
enum LaunchAtLogin {

    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        available && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard available else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// 자동 시작 기록은 번들 ID와 앱 경로에 묶여 있어서 옛 TokenCat 앱의 기록은 이어지지 않는다.
    /// install.sh가 옛 앱에서 켜져 있던 것을 남겨 두면 이 앱으로 다시 등록한다.
    static func restoreAfterRename() {
        let key = "restoreLaunchAtLogin"
        guard available, UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        try? set(true)
    }
}

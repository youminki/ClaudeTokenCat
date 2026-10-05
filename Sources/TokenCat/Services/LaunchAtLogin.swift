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
}

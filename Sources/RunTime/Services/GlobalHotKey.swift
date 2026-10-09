import AppKit
import Carbon.HIToolbox

/// 어느 앱을 쓰고 있든 ⌃⌥U로 사용량 창을 연다. Carbon 단축키는 손쉬운 사용 권한 없이 동작한다.
/// 다른 앱 단축키와 겹치지 않도록 잘 쓰지 않는 control+option 조합을 고른다.
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    static let displayName = "⌃⌥U"

    var action: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var isRegistered: Bool { hotKey != nil }

    private init() {}

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { GlobalHotKey.shared.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5254_494D), id: 1)   // 'RTIM'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_U), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil   // 다른 앱이 같은 조합을 먼저 잡은 경우 (eventHotKeyExistsErr)
            NSLog("[RunTime] 단축키 등록 실패: %d", status)
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}

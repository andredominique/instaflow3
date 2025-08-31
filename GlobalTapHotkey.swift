import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let tapTempoGlobalTap = Notification.Name("tapTempoGlobalTap")
}

final class GlobalTapHotkey {
    static let shared = GlobalTapHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Register global hotkey (default: Control + Option + Space)
    func register(
        keyCode: UInt32 = UInt32(49), // Space key
        modifiers: UInt32 = UInt32(controlKey) | UInt32(optionKey)
    ) {
        unregister()

        // Install a handler for hotkey events
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { (_, _, _) -> OSStatus in
            NotificationCenter.default.post(name: .tapTempoGlobalTap, object: nil)
            return noErr
        }

        var handler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec, nil, &handler)
        self.eventHandler = handler

        // Register the actual hotkey
        let hotKeyID = EventHotKeyID(signature: OSType("TTMP".fourCharCodeValue), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit { unregister() }
}

// Helper to make OSType from a 4-char string like "TTMP"
private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        if let data = self.data(using: .macOSRoman) { // ✅ correct case
            for (i, byte) in data.enumerated() where i < 4 {
                result |= FourCharCode(byte) << ((3 - i) * 8)
            }
        }
        return result
    }
}

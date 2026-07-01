import Carbon.HIToolbox
import AppKit

/// Registers a system-wide keyboard shortcut using the Carbon Event Manager.
/// This doesn't require Accessibility permission (unlike NSEvent global monitors)
/// and works for unsandboxed apps like Portly.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(keyCode: UInt32 = UInt32(kVK_ANSI_P),
         modifiers: UInt32 = UInt32(cmdKey | shiftKey),
         onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(bitPattern: 0x504F5254), id: 1) // "PORT"

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let userData, let eventRef else { return noErr }
                var receivedID = EventHotKeyID()
                GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onTrigger()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

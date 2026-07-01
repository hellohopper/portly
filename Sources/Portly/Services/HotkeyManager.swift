import Carbon.HIToolbox
import AppKit

/// Registers a system-wide keyboard shortcut using the Carbon Event Manager.
/// This doesn't require Accessibility permission (unlike NSEvent global monitors)
/// and works for unsandboxed apps like Portly.
final class HotkeyManager {
    static let defaultKeyCode = UInt32(kVK_ANSI_P)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)
    private static let keyCodeDefaultsKey = "hotkeyKeyCode"
    private static let modifiersDefaultsKey = "hotkeyModifiers"

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    static var storedKeyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: keyCodeDefaultsKey) as? Int
        return stored.map(UInt32.init) ?? defaultKeyCode
    }

    static var storedModifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: modifiersDefaultsKey) as? Int
        return stored.map(UInt32.init) ?? defaultModifiers
    }

    static func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeDefaultsKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersDefaultsKey)
    }

    init(keyCode: UInt32 = HotkeyManager.storedKeyCode,
         modifiers: UInt32 = HotkeyManager.storedModifiers,
         onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register(keyCode: keyCode, modifiers: modifiers)
    }

    /// Tears down the current registration and installs a new key combo.
    func reregister(keyCode: UInt32, modifiers: UInt32) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
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

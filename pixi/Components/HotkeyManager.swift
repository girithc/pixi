//
//  HotkeyManager.swift
//  pixi
//
//  Registers system-wide hotkeys via Carbon's RegisterEventHotKey.
//  This API reserves the shortcut at the system level, so it fires
//  even when Pixi is not frontmost, and needs no special permission.
//

import Carbon
import AppKit

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// Register a system-wide hotkey. `id` must be unique across registrations.
    func register(keyCode: Int, modifiers: UInt32, id: UInt32,
                  handler: @escaping () -> Void) {
        installHandler()
        guard refs[id] == nil else { return }
        handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: Self.fourCharCode("pixi"), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            print("RegisterEventHotKey(\(id)) failed: \(status)")
            handlers.removeValue(forKey: id)
            return
        }
        refs[id] = ref
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs.removeValue(forKey: id)
        }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &spec,
            userData,
            &eventHandler
        )
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    /// Pack up to 4 ASCII bytes into an OSType signature.
    static func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
}

// C-function-pointer event handler — must not capture state.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    var actualSize: UInt = 0
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        &actualSize,
        &hotKeyID
    )

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { manager.fire(id: hotKeyID.id) }
    return noErr
}

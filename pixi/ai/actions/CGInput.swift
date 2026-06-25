//
//  CGInput.swift
//  pixi
//
//  Low-level human-input primitives via CGEvent — the same events a real
//  keyboard/mouse produce. One source of truth for posting input so the
//  primitive tools stay thin and a bug maps here, not to each tool.
//
//  Created by Girith Choudhary on 6/25/26.
//

import CoreGraphics

@MainActor
enum CGInput {
    /// Normalized (0..1, top-left) → global CG display coords.
    static func screenPoint(x: Double, y: Double) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: bounds.origin.x + x * bounds.width,
                       y: bounds.origin.y + y * bounds.height)
    }

    /// Post a mouse click (left/right, single or double) at a global point.
    static func click(at point: CGPoint, button: CGMouseButton, count: Int = 1) {
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        for _ in 0..<count {
            let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                               mouseCursorPosition: point, mouseButton: button)
            let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                             mouseCursorPosition: point, mouseButton: button)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Type a string as per-character unicode key events.
    static func typeText(_ text: String) {
        for ch in text {
            var chars = [UniChar](ch.unicodeScalars.map { UniChar($0.value) })
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Press a virtual key with optional modifier flags.
    static func pressKey(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    /// Scroll: wheel1 = vertical (dy), wheel2 = horizontal (dx), in pixels.
    static func scroll(dy: Int32, dx: Int32 = 0) {
        let evt = CGEvent(scrollWheelEvent2Source: nil,
                          units: .pixel,
                          wheelCount: 2,
                          wheel1: dy,
                          wheel2: dx,
                          wheel3: 0)
        evt?.post(tap: .cghidEventTap)
    }
}

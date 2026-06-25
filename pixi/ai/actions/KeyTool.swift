//
//  KeyTool.swift
//  pixi
//
//  Press a key (with optional modifiers) — like a human hitting a
//  keyboard shortcut. Key names: a-z, 0-9, return, escape, tab, delete,
//  space, up/down/left/right, home, end, pageup, pagedown, f1-f12.
//  Modifiers: cmd, shift, ctrl, opt.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Carbon
import CoreGraphics

@MainActor
struct KeyTool: Tool {
    let name = "key"
    let summary = "Press a key / shortcut."
    let description = "Press a key with optional modifiers (keyboard shortcut). key: a-z, 0-9, return, escape, tab, delete, space, up/down/left/right, home, end, pageup, pagedown, f1-f12. modifiers: cmd, shift, ctrl, opt. Use to submit (return), cancel (escape), navigate, or trigger shortcuts (e.g. cmd+k, cmd+t)."
    let argsSchema = "{\"key\": \"return\", \"modifiers\": [\"cmd\"]}"

    private let keyMap: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab,
        "delete": kVK_Delete, "space": kVK_Space,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12
    ]

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let key = args["key"] as? String,
              let code = keyMap[key.lowercased()] else {
            return ToolResult(ok: false, output: "", error: "unknown key: \(args["key"] ?? "?")")
        }
        var flags = CGEventFlags()
        if let mods = args["modifiers"] as? [String] {
            for m in mods {
                switch m.lowercased() {
                case "cmd", "command": flags.insert(.maskCommand)
                case "shift": flags.insert(.maskShift)
                case "ctrl", "control": flags.insert(.maskControl)
                case "opt", "option", "alt": flags.insert(.maskAlternate)
                default: break
                }
            }
        }
        CGInput.pressKey(virtualKey: CGKeyCode(code), flags: flags)
        let modStr = (args["modifiers"] as? [String])?.joined(separator: "+") ?? ""
        return ToolResult(ok: true,
                          output: "key \(modStr.isEmpty ? "" : modStr + "+")\(key.lowercased())",
                          error: nil)
    }
}

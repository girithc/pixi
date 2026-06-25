//
//  SystemSettingsTool.swift
//  pixi
//
//  Open a System Settings pane via the x-apple.systempreferences: URL
//  scheme. Native, no permission needed. Restored: faster + more reliable
//  than clicking through Settings by vision.
//
//  Created by Girith Choudhary on 6/25/26.
//

import AppKit

@MainActor
struct SystemSettingsTool: Tool {
    let name = "open_settings"
    let summary = "Open a System Settings pane."
    let description = "Open a macOS System Settings pane directly via deep link (e.g. wifi, bluetooth, appearance, sound, displays, privacy, accessibility, microphone). Faster and more reliable than clicking through Settings with vision. Use when the goal involves a system preference pane."
    let argsSchema = "{\"pane\": \"<pane id or name>\"}"

    private let panes: [String: String] = [
        "wifi": "com.apple.wifi", "bluetooth": "com.apple.Bluetooth",
        "network": "com.apple.Network", "appearance": "com.apple.Appearance",
        "wallpaper": "com.apple.Wallpaper", "screensaver": "com.apple.ScreenSaver",
        "displays": "com.apple.Displays", "sound": "com.apple.Sound",
        "notifications": "com.apple.Notifications", "focus": "com.apple.Focus",
        "general": "com.apple.General", "controlcenter": "com.apple.ControlCenter",
        "siri": "com.apple.Siri", "spotlight": "com.apple.Spotlight",
        "privacy": "com.apple.preference.security",
        "accessibility": "com.apple.preference.security?Privacy_Accessibility",
        "microphone": "com.apple.preference.security?Privacy_Microphone",
        "screen": "com.apple.preference.security?Privacy_ScreenCapture",
        "battery": "com.apple.Battery", "keyboard": "com.apple.Keyboard",
        "trackpad": "com.apple.Trackpad", "mouse": "com.apple.Mouse",
        "sharing": "com.apple.preferences.sharing", "appleid": "com.apple.appleID"
    ]

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let pane = args["pane"] as? String, !pane.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'pane'")
        }
        let key = pane.lowercased()
        let id = panes[key] ?? panes[key.replacingOccurrences(of: " ", with: "")] ?? pane
        let urlString = "x-apple.systempreferences:\(id)"
        guard let url = URL(string: urlString) else {
            return ToolResult(ok: false, output: "", error: "bad url: \(urlString)")
        }
        let ok = NSWorkspace.shared.open(url)
        return ok
            ? ToolResult(ok: true, output: "opened \(id)", error: nil)
            : ToolResult(ok: false, output: "", error: "failed to open \(id)")
    }
}

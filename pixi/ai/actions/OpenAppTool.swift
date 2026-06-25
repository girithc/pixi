//
//  OpenAppTool.swift
//  pixi
//
//  Open an application by name via `open -a`. Native, no permission needed.
//  Restored: vision alone can't open an app that isn't running.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

@MainActor
struct OpenAppTool: Tool {
    let name = "open_app"
    let summary = "Launch an installed app — ONLY after list_apps confirms the exact name; never assume."
    let description = "Launch a macOS application by name (e.g. Safari, Terminal, Notes). Use when the goal needs an app that is NOT already running. NEVER assume an app is installed from Dock icons or screenshots — call list_apps first and confirm the exact name appears, then open_app. If the app may already be open, call list_running_apps and activate it instead of re-launching."
    let argsSchema = "{\"app\": \"<name>\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let app = args["app"] as? String, !app.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'app'")
        }
        let p = Process()
        p.launchPath = "/usr/bin/open"
        p.arguments = ["-a", app]
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                return ToolResult(ok: true, output: "opened \(app)", error: nil)
            }
            return ToolResult(ok: false, output: "",
                              error: "'\(app)' not found — call list_apps to see installed apps, then retry or pivot")
        } catch {
            return ToolResult(ok: false, output: "", error: "\(error)")
        }
    }
}

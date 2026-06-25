//
//  AppleScriptTool.swift
//  pixi
//
//  Run an AppleScript via `osascript`. Covers `set volume N`, telling
//  scriptable apps (Safari/Notes/Mail/Messages/Calendar) to do things.
//  Restored: native app control vision can't do directly.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

@MainActor
struct AppleScriptTool: Tool {
    let name = "applescript"
    let summary = "Run AppleScript on a scriptable app — confirm it's installed/running first (list_apps)."
    let description = "Run an AppleScript via osascript. Use for native app actions vision/AX can't do cleanly: 'set volume N', 'tell application \"Safari\" to open location \"...\"', 'tell application \"Notes\" to make note', activate/quit apps, query state. The target app must be scriptable (Safari, Notes, Mail, Messages, Calendar, Finder, etc.)."
    let argsSchema = "{\"script\": \"<applescript>\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let script = args["script"] as? String, !script.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'script'")
        }
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if p.terminationStatus == 0 {
                return ToolResult(ok: true, output: out, error: nil)
            }
            return ToolResult(ok: false, output: "",
                              error: out.isEmpty ? "osascript exit \(p.terminationStatus)" : out)
        } catch {
            return ToolResult(ok: false, output: "", error: "\(error)")
        }
    }
}

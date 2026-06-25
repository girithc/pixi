//
//  ListRunningAppsTool.swift
//  pixi
//
//  List currently-running macOS apps via NSWorkspace. The agent calls this
//  to see what's already open (avoid re-launching, or switch to a running
//  app). Fast, no permission. Regular apps only (no background agents).
//
//  Created by Girith Choudhary on 6/25/26.
//

import AppKit

@MainActor
struct ListRunningAppsTool: Tool {
    let name = "list_running_apps"
    let summary = "Currently-running apps + frontmost."
    let description = "Returns the currently-running macOS apps (already open) plus which is frontmost. Call to decide whether to switch to an already-open app (activate it) instead of launching a new one, or to detect if a specific app is open without using vision."
    let argsSchema = "{}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
        let unique = Array(Set(names)).sorted()
        let list = unique.joined(separator: ", ")
        let out = front.map { "\(list) | frontmost: \($0)" } ?? list
        return ToolResult(ok: true, output: out, error: nil)
    }
}

//
//  TypeTool.swift
//  pixi
//
//  Type a string as per-character unicode key events — like a human
//  typing at the current keyboard focus. Click into a field first.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

@MainActor
struct TypeTool: Tool {
    let name = "type"
    let summary = "Type text at current focus."
    let description = "Type a string at the current keyboard focus — like a human typing. Click into or focus a text field first (click or ax_press), then type. Use for entering text the AX tree can't set via ax_set_value (e.g. web input fields)."
    let argsSchema = "{\"text\": \"hello\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let text = args["text"] as? String, !text.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'text'")
        }
        CGInput.typeText(text)
        return ToolResult(ok: true, output: "typed \(text.count) chars", error: nil)
    }
}

//
//  ScrollTool.swift
//  pixi
//
//  Scroll the wheel — like a human scrolling. dy = vertical pixels
//  (positive = down), dx = horizontal pixels.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

@MainActor
struct ScrollTool: Tool {
    let name = "scroll"
    let summary = "Scroll the wheel (dx/dy)."
    let description = "Scroll the mouse wheel. dy: vertical pixels (positive = down, negative = up). Optional dx: horizontal pixels. Use to reveal content off-screen (search results, long lists) before clicking. ~200-400 px per step."
    let argsSchema = "{\"dy\": 200, \"dx\": 0}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        let dy = (args["dy"] as? Int).map(Int32.init)
                ?? (args["dy"] as? Double).map { Int32($0) } ?? 0
        let dx = (args["dx"] as? Int).map(Int32.init)
                ?? (args["dx"] as? Double).map { Int32($0) } ?? 0
        CGInput.scroll(dy: dy, dx: dx)
        return ToolResult(ok: true, output: "scroll dy=\(dy) dx=\(dx)", error: nil)
    }
}

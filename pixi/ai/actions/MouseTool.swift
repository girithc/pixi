//
//  MouseTool.swift
//  pixi
//
//  Human-like mouse click. The vision LLM picks normalized coordinates
//  from the screenshot; this posts the real CGEvent at the mapped screen
//  point. Supports left/right + double-click via args.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation
import CoreGraphics

@MainActor
struct MouseTool: Tool {
    let name = "click"
    let summary = "Click at normalized screen coords."
    let description = "Click the mouse at normalized (0..1) screen coordinates from the image TOP-LEFT. Args: x, y (required), button ('left' default or 'right'), double (true for double-click). Use for human-like clicks on visible targets not in the AX tree. Coordinates must come from what you see in the screenshot — be precise."
    let argsSchema = "{\"x\": 0.5, \"y\": 0.5, \"button\": \"left\", \"double\": false}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let x = (args["x"] as? Double) ?? (args["x"] as? Int).map(Double.init),
              let y = (args["y"] as? Double) ?? (args["y"] as? Int).map(Double.init) else {
            return ToolResult(ok: false, output: "", error: "missing args 'x'/'y'")
        }
        let button: CGMouseButton = (args["button"] as? String == "right") ? .right : .left
        let count = (args["double"] as? Bool == true) ? 2 : 1
        let point = CGInput.screenPoint(x: x, y: y)
        CGInput.click(at: point, button: button, count: count)
        return ToolResult(ok: true,
                          output: "\(button == .right ? "right" : "left") click\(count == 2 ? " x2" : "") at \(point)",
                          error: nil)
    }
}

//
//  VisionClickTool.swift
//  pixi
//
//  Vision-grounded click: capture the screen, ask the vision LLM to locate
//  the element for a goal, then click the first target's center via CGInput.
//  Use when the target isn't in the AX tree and you'd rather delegate
//  grounding than emit click coords yourself. Attaches screenshot + targets
//  to the interaction for inspection.
//
//  Created by Girith Choudhary on 6/25/26.
//

import AppKit
import CoreGraphics

@MainActor
struct VisionClickTool: Tool {
    let name = "vision_click"
    let summary = "Locate-by-goal via vision, then click."
    let description = "Locate a UI element by natural-language goal via the vision model, then click its center. Use as a fallback when the target is NOT in the AX tree and you can't pinpoint exact click coords from the screenshot yourself (e.g. web content, custom-drawn UI). Slower than click (extra vision call) — prefer click with precise coords or ax_press when possible."
    let argsSchema = "{\"goal\": \"<what to click>\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let goal = args["goal"] as? String, !goal.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'goal'")
        }
        guard let (cg, frame) = await ScreenCapture.captureMainScreen() else {
            return ToolResult(ok: false, output: "", error: "screen capture failed")
        }

        let png = pngData(cg)
        let prompt = "The user wants to click the element to: \(goal). " +
            "Locate the single best UI element to click. " +
            "Return ONLY JSON: {\"targets\":[{\"label\":...,\"x\":..,\"y\":..,\"w\":..,\"h\":..,\"reason\":...}]} " +
            "with x,y,w,h normalized 0..1 from the image top-left."
        let engine = FireworksVisionLLM(modelId: AppSettings.shared.visionModelId,
                                        apiKey: AppSettings.shared.fireworksKey)
        let raw: String
        do {
            raw = try await engine.analyze(imageData: png, prompt: prompt)
        } catch {
            return ToolResult(ok: false, output: "", error: "vision: \(error)")
        }

        let targets = TargetParser.parse(raw)
        AITrace.shared.attachMedia(
            id: interactionId,
            screenshot: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
            targets: targets, frame: frame)

        guard let first = targets.first else {
            return ToolResult(ok: false, output: String(raw.prefix(200)),
                              error: "vision returned no targets")
        }

        let cx = first.x + first.w / 2
        let cy = first.y + first.h / 2
        let point = CGInput.screenPoint(x: cx, y: cy)
        CGInput.click(at: point, button: .left, count: 1)

        return ToolResult(ok: true,
                          output: "clicked \(first.label ?? goal) at \(point)", error: nil)
    }

    private func pngData(_ cg: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

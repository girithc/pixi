//
//  ToolRegistry.swift
//  pixi
//
//  The DO layer. Each native capability is a `Tool` (one file in actions/).
//  The registry holds the manifest fed to the reasoning LLM and dispatches
//  by name. Every tool logs its own trace step so a failure maps to one
//  file. One source of truth — no duplicated copies.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

struct ToolResult {
    let ok: Bool
    let output: String
    let error: String?
}

@MainActor
protocol Tool {
    var name: String { get }
    var summary: String { get }       // one-line, injected in every prompt (compact)
    var description: String { get }   // detailed use-case guidance (list_tools, not every prompt)
    var argsSchema: String { get }    // arg shape for the LLM
    func run(args: [String: Any], interactionId: UUID) async -> ToolResult
}

@MainActor
enum ToolRegistry {
    static let tools: [Tool] = [
        OpenAppTool(),
        ListAppsTool(),
        ListRunningAppsTool(),
        ArrangeWindowsTool(),
        ListToolsTool(),
        SystemSettingsTool(),
        AppleScriptTool(),
        AXPressTool(),
        AXSetValueTool(),
        MouseTool(),
        TypeTool(),
        KeyTool(),
        ScrollTool(),
        VisionClickTool(),
        DoneTool()
    ]

    /// Compact manifest for every prompt: name — summary | args. No full
    /// descriptions (avoids bloat). Agent calls `list_tools` for use-cases.
    static var manifest: String {
        tools.map { "- \($0.name): \($0.summary) | args: \($0.argsSchema)" }
            .joined(separator: "\n")
    }

    /// Full manifest with detailed use-case descriptions (returned by list_tools).
    static var fullManifest: String {
        tools.map { "- \($0.name): \($0.description) | args: \($0.argsSchema)" }
            .joined(separator: "\n")
    }

    static func dispatch(name: String, args: [String: Any],
                         interactionId: UUID) async -> ToolResult {
        let t0 = Date()
        let result: ToolResult
        if let tool = tools.first(where: { $0.name == name }) {
            result = await tool.run(args: args, interactionId: interactionId)
        } else {
            result = ToolResult(ok: false, output: "", error: "unknown tool: \(name)")
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        AITrace.shared.addStep(
            to: interactionId, kind: .tool, label: name,
            input: argsDescription(args),
            output: result.ok ? result.output : (result.error ?? "failed"),
            status: result.ok ? .success : .failed,
            durationMs: ms)
        return result
    }

    private static func argsDescription(_ args: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}

/// Sentinel tool: the LLM returns this when the task is complete.
@MainActor
struct DoneTool: Tool {
    let name = "done"
    let summary = "Signal that the goal is achieved."
    let description = "Call when the user's goal is already achieved and no further action is needed."
    let argsSchema = "{}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        ToolResult(ok: true, output: "done", error: nil)
    }
}

/// On-demand: return full tool descriptions + use-cases. Lets the agent
/// learn when to use each tool without bloating every prompt.
@MainActor
struct ListToolsTool: Tool {
    let name = "list_tools"
    let summary = "Get detailed use-case descriptions of every tool."
    let description = "Returns the full manifest: each tool's name, detailed description, and args. Call once if unsure which tool to use or what an action does."
    let argsSchema = "{}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        ToolResult(ok: true, output: ToolRegistry.fullManifest, error: nil)
    }
}

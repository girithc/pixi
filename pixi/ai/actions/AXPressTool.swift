//
//  AXPressTool.swift
//  pixi
//
//  Press a UI element by AX role + optional title. Uses the Accessibility
//  tree — exact element, no coords, no vision. Needs Accessibility TCC.
//  Restored: precise for real controls the AX tree exposes.
//
//  Created by Girith Choudhary on 6/25/26.
//

import ApplicationServices

@MainActor
struct AXPressTool: Tool {
    let name = "ax_press"
    let summary = "Press a control by AX role+title."
    let description = "Press a UI control in the frontmost app by Accessibility role + optional title (e.g. AXButton \"OK\", AXCheckBox \"Bluetooth\"). PREFER this over click when the target is in the AX tree — exact element, no coordinate guessing. Needs Accessibility permission. Read the AX tree in the prompt to get role+title."
    let argsSchema = "{\"role\": \"AXButton\", \"title\": \"OK\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let role = args["role"] as? String, !role.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'role'")
        }
        let title = args["title"] as? String
        guard let element = AccessibilityTree.find(role: role, title: title) else {
            return ToolResult(ok: false, output: "",
                              error: "no AX element: role=\(role) title=\(title ?? "nil")")
        }
        let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if err == .success {
            return ToolResult(ok: true,
                              output: "pressed \(role) \"\(title ?? "")\"", error: nil)
        }
        return ToolResult(ok: false, output: "", error: "AXPress failed: \(err)")
    }
}

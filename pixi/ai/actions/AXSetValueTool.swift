//
//  AXSetValueTool.swift
//  pixi
//
//  Set the value of an AX element by role + optional title (text fields,
//  sliders). Uses the Accessibility tree — exact element. Needs
//  Accessibility TCC. Restored: precise input for fields the AX tree exposes.
//
//  Created by Girith Choudhary on 6/25/26.
//

import ApplicationServices

@MainActor
struct AXSetValueTool: Tool {
    let name = "ax_set_value"
    let summary = "Set a control's value by AX role+title."
    let description = "Set the value of a control in the frontmost app by AX role + optional title (text fields, sliders, search fields). PREFER this over click+type when the field is in the AX tree — sets the value directly, no coordinate guessing. Needs Accessibility permission. value is a string (numbers auto-converted for sliders)."
    let argsSchema = "{\"role\": \"AXTextField\", \"title\": \"\", \"value\": \"50\"}"

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        guard let role = args["role"] as? String, !role.isEmpty else {
            return ToolResult(ok: false, output: "", error: "missing arg 'role'")
        }
        guard let value = args["value"] as? String else {
            return ToolResult(ok: false, output: "", error: "missing arg 'value'")
        }
        let title = args["title"] as? String
        guard let element = AccessibilityTree.find(role: role, title: title) else {
            return ToolResult(ok: false, output: "",
                              error: "no AX element: role=\(role) title=\(title ?? "nil")")
        }
        var err = AXUIElementSetAttributeValue(element,
                                               kAXValueAttribute as CFString, value as CFTypeRef)
        if err != .success, let d = Double(value) {
            err = AXUIElementSetAttributeValue(element,
                                               kAXValueAttribute as CFString, d as CFTypeRef)
        }
        if err == .success {
            return ToolResult(ok: true,
                              output: "set \(role) \"\(title ?? "")\" = \(value)", error: nil)
        }
        return ToolResult(ok: false, output: "", error: "AXSetValue failed: \(err)")
    }
}

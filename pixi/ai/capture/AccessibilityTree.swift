//
//  AccessibilityTree.swift
//  pixi
//
//  Harvests a compact text snapshot of the frontmost app's focused window
//  from the Accessibility tree, and finds elements by role+title for the
//  AX tools. Vision-only grounding is imprecise; AX roles + titles + frames
//  make the target unambiguous. Requires Accessibility TCC.
//
//  Created by Girith Choudhary on 6/24/26.
//

import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum AccessibilityTree {
    private static let maxDepth = 4
    private static let maxElements = 120
    private static let searchMaxDepth = 6

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
        "AXTextField", "AXTextArea", "AXMenuItem", "AXMenu",
        "AXLink", "AXTab", "AXToolbar", "AXSlider", "AXComboBox",
        "AXMenuButton", "AXSearchField", "AXStaticText", "AXSwitch"
    ]

    /// Returns a compact, normalized AX tree string, or "" if not trusted.
    static func snapshotFrontmost() -> String {
        guard AXIsProcessTrusted() else { return "" }
        guard let app = NSWorkspace.shared.frontmostApplication else { return "" }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement,
                                      kAXFocusedWindowAttribute as CFString, &focused)
        guard let focused else { return "" }
        let window = focused as! AXUIElement

        guard let screen = NSScreen.main else { return "" }
        let sw = screen.frame.width
        let sh = screen.frame.height

        var lines: [String] = []
        var count = 0
        walk(window, depth: 0, screenW: sw, screenH: sh,
             lines: &lines, count: &count)
        return lines.joined(separator: "\n")
    }

    /// Find the first AX element in the frontmost app matching role (+ optional title).
    static func find(role: String, title: String?) -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var found: AXUIElement?
        search(appElement, role: role, title: title, found: &found, depth: 0)
        return found
    }

    private static func walk(_ element: AXUIElement, depth: Int,
                             screenW: CGFloat, screenH: CGFloat,
                             lines: inout [String], count: inout Int) {
        guard count < maxElements, depth <= maxDepth else { return }

        let role = string(element, kAXRoleAttribute)
        let title = string(element, kAXTitleAttribute)
        let frame = normalizedFrame(element, screenW: screenW, screenH: screenH)

        let isInteractive = interactiveRoles.contains(role ?? "")
        let hasTitle = !(title?.isEmpty ?? true)
        if frame != nil, isInteractive || hasTitle {
            let indent = String(repeating: "  ", count: depth)
            let label = hasTitle ? " \"\(title!)\"" : ""
            lines.append("\(indent)\(role ?? "?")\(label) \(frame!)")
            count &+= 1
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element,
                                      kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else { return }
        for child in kids {
            walk(child, depth: depth + 1, screenW: screenW, screenH: screenH,
                 lines: &lines, count: &count)
            if count >= maxElements { break }
        }
    }

    private static func search(_ element: AXUIElement, role: String, title: String?,
                               found: inout AXUIElement?, depth: Int) {
        guard found == nil, depth <= searchMaxDepth else { return }
        let r = string(element, kAXRoleAttribute)
        let t = string(element, kAXTitleAttribute)
        if r == role, title == nil || t == title {
            found = element
            return
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element,
                                      kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else { return }
        for child in kids {
            search(child, role: role, title: title, found: &found, depth: depth + 1)
            if found != nil { return }
        }
    }

    private static func string(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        return value as? String
    }

    private static func normalizedFrame(_ element: AXUIElement,
                                        screenW: CGFloat, screenH: CGFloat) -> String? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element,
                                      kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(element,
                                      kAXSizeAttribute as CFString, &sizeVal)
        guard let posVal, let sizeVal,
              let pos = axPoint(posVal), let size = axSize(sizeVal) else { return nil }
        return String(format: "[x=%.3f y=%.3f w=%.3f h=%.3f]",
                      pos.x / screenW, pos.y / screenH,
                      size.width / screenW, size.height / screenH)
    }

    private static func axPoint(_ value: CFTypeRef) -> CGPoint? {
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ value: CFTypeRef) -> CGSize? {
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

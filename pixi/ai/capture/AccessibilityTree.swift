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
    /// Depth to walk when printing the tree. Deep enough to reach sheet/dialog
    /// buttons in dense apps (Xcode), bounded to avoid runaway traversal.
    private static let maxDepth = 8
    /// Hard safety cap on nodes walked (bounds prompt size + time).
    private static let maxWalk = 2000
    /// Budget for non-actionable titled elements (labels, groups, static text).
    /// Actionable elements below are NEVER dropped — they're the press targets.
    private static let staticBudget = 60
    private static let searchMaxDepth = 6

    /// Actionable roles — always included in the printed tree regardless of the
    /// static budget. These are the elements `ax_press` / `ax_set_value` target.
    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
        "AXTextField", "AXTextArea", "AXMenuItem", "AXMenu",
        "AXLink", "AXTab", "AXToolbar", "AXSlider", "AXComboBox",
        "AXMenuButton", "AXSearchField", "AXSwitch", "AXSheet"
    ]

    /// Returns a compact, normalized AX tree string, or "" if not trusted.
    /// Stack-style priority: actionable elements (buttons, menu items, fields,
    /// sheets) always survive the cap; only static/structural text is budgeted.
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
        var walked = 0
        var staticCount = 0
        walk(window, depth: 0, screenW: sw, screenH: sh,
             lines: &lines, walked: &walked, staticCount: &staticCount)
        return lines.joined(separator: "\n")
    }

    /// Frame (screen coords, top-left origin y-down) of the frontmost app's
    /// focused window, for cropping screenshots to the app being operated on.
    static func focusedWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement,
                                      kAXFocusedWindowAttribute as CFString, &focused)
        guard let focused else { return nil }
        return cgFrame(focused as! AXUIElement)
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
                             lines: inout [String],
                             walked: inout Int, staticCount: inout Int) {
        guard walked < maxWalk, depth <= maxDepth else { return }
        walked &+= 1

        let role = string(element, kAXRoleAttribute)
        let title = string(element, kAXTitleAttribute)
        let frame = normalizedFrame(element, screenW: screenW, screenH: screenH)

        let isInteractive = interactiveRoles.contains(role ?? "")
        let hasTitle = !(title?.isEmpty ?? true)
        if let frame {
            if isInteractive {
                // Actionable target — always include, never budgeted out.
                let indent = String(repeating: "  ", count: depth)
                let label = hasTitle ? " \"\(title!)\"" : ""
                lines.append("\(indent)\(role ?? "?")\(label) \(frame)")
            } else if hasTitle, staticCount < staticBudget {
                staticCount &+= 1
                let indent = String(repeating: "  ", count: depth)
                lines.append("\(indent)\(role ?? "?") \"\(title!)\" \(frame)")
            }
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element,
                                      kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else { return }
        for child in kids {
            walk(child, depth: depth + 1, screenW: screenW, screenH: screenH,
                 lines: &lines, walked: &walked, staticCount: &staticCount)
            if walked >= maxWalk { break }
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

    /// Raw frame (points, screen coords top-left y-down) of an AX element.
    private static func cgFrame(_ element: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element,
                                      kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(element,
                                      kAXSizeAttribute as CFString, &sizeVal)
        guard let posVal, let sizeVal,
              let pos = axPoint(posVal), let size = axSize(sizeVal) else { return nil }
        return CGRect(origin: pos, size: size)
    }
}

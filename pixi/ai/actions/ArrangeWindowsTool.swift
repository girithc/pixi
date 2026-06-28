//
//  ArrangeWindowsTool.swift
//  pixi
//
//  One-shot auto-tiling, no screenshot. Enumerates every on-screen app
//  window via Accessibility, divides the visible screen into a balanced
//  grid of cells (equal-ish, edge-to-edge, no gaps), asks the text LLM
//  which window should go in which cell (from app name + title alone),
//  then animates each window to its assigned cell via AX position+size.
//  Falls back to in-order placement if the LLM call fails. No image, no
//  Screen Recording TCC — Accessibility only.
//
//  Created by Girith Choudhary on 6/25/26.
//

import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
struct ArrangeWindowsTool: Tool {
    let name = "arrange_windows"
    let summary = "Rearrange/tile/organize all open windows to fill the screen — the DEFAULT meaning of 'rearrange tabs/windows/apps'."
    let description = "Rearranges every open app window to fit the main screen in a balanced grid (edge-to-edge, no white space), smoothly animated. Enumerates windows via Accessibility, divides the screen into cells, asks the text LLM to assign each window to a cell from app name + title, then animates each window to its cell via AX. DEFAULT: 'rearrange/organize/tidy/tile tabs/windows/apps' means tiling app windows across the screen — call THIS. Only treat 'tabs' as in-app browser tab reorder if the user explicitly names one app's tabs (e.g. 'rearrange Safari's tabs') — and there is no tool for that, so say so. Optional hint biases placement (e.g. hint='put Safari in the big cell'). Needs Accessibility TCC only."
    let argsSchema = "{\"hint\": \"<optional placement preference>\"}"

    private struct Win {
        let element: AXUIElement
        let app: String
        let title: String
    }

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        let t0 = Date()
        guard AXIsProcessTrusted() else {
            return ToolResult(ok: false, output: "",
                              error: "Accessibility not trusted — grant TCC")
        }
        guard let screen = NSScreen.main else {
            return ToolResult(ok: false, output: "", error: "no main screen")
        }

        // 1. Enumerate on-screen windows (AX). No screenshot.
        let wins = enumerateWindows()
        guard !wins.isEmpty else {
            return ToolResult(ok: false, output: "", error: "no open windows found")
        }

        // 2. Divide the visible screen into N balanced cells (normalized,
        //    top-left origin y-down). Same count as windows.
        let cells = balancedCells(count: wins.count)
        guard cells.count == wins.count else {
            return ToolResult(ok: false, output: "", error: "cell count mismatch")
        }

        // 3. Assign windows → cells. LLM picks placement from app+title;
        //    fall back to in-order on any failure.
        let hint = (args["hint"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var assignment: [Int] = Array(0..<wins.count)   // window i → cell i
        if let llm = await assignCells(wins: wins, cells: cells, hint: hint) {
            assignment = llm
        }

        // 4. Build animation list (element, start frame, target cell in AX px).
        var anims: [(AXUIElement, CGRect, CGRect)] = []
        for (wi, ci) in assignment.enumerated() {
            guard ci >= 0, ci < cells.count else { continue }
            let target = axRect(normalized: cells[ci], screen: screen)
            let el = wins[wi].element
            let start = frameOf(el) ?? target
            anims.append((el, start, target))
        }

        // 5. Animate all windows to their cells in sync — no jolt.
        let applied = await animate(anims, duration: 0.12, steps: 10)

        let out = "arranged \(applied)/\(wins.count) windows"
        _ = Int(Date().timeIntervalSince(t0) * 1000)
        return ToolResult(ok: applied > 0, output: out,
                          error: applied == 0 ? "no windows moved" : nil)
    }

    // MARK: - Animation

    /// Step every window from start→target together each frame. Parallel
    /// visual movement (all advance per tick), ease-in-out, final tick snaps
    /// to exact target to kill float drift. Returns count fully moved.
    private func animate(_ anims: [(AXUIElement, CGRect, CGRect)],
                         duration: Double, steps: Int) async -> Int {
        guard !anims.isEmpty else { return 0 }
        let interval = UInt64((duration / Double(steps)) * 1_000_000_000)
        var ok = Array(repeating: false, count: anims.count)
        for i in 1...steps {
            let t = easeInOut(Double(i) / Double(steps))
            for j in (anims.startIndex..<anims.endIndex) {
                let (el, start, target) = anims[j]
                _ = setWindowFrame(el, lerpRect(start, target, t))
            }
            if i < steps { try? await Task.sleep(nanoseconds: interval) }
        }
        // Final exact snap + tally.
        for j in (anims.startIndex..<anims.endIndex) {
            let (el, _, target) = anims[j]
            if setWindowFrame(el, target) { ok[j] = true }
        }
        return ok.filter { $0 }.count
    }

    private func easeInOut(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    private func lerpRect(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let f = CGFloat(t)
        return CGRect(x: a.origin.x + (b.origin.x - a.origin.x) * f,
                      y: a.origin.y + (b.origin.y - a.origin.y) * f,
                      width: a.size.width + (b.size.width - a.size.width) * f,
                      height: a.size.height + (b.size.height - a.size.height) * f)
    }

    // MARK: - Window enumeration

    /// All non-minimized, movable windows of running regular apps. pixi's own
    /// menu/main window is included (it's movable); pixi's overlay panels
    /// (CursorBuddy, InputSpace) are skipped by their tagged AX identifier so
    /// the buddy stays glued to the real cursor and the command bar isn't tiled.
    private let excludedIds: Set<String> = ["pixi.cursorbuddy", "pixi.inputspace"]

    private func enumerateWindows() -> [Win] {
        var out: [Win] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let name = app.localizedName else { continue }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref)
            guard let wins = ref as? [AXUIElement] else { continue }
            for win in wins {
                if isMinimized(win) { continue }
                if let id = identifier(win), excludedIds.contains(id) { continue }
                if !isMovable(win) { continue }
                let title = string(win, kAXTitleAttribute) ?? ""
                guard let f = frameOf(win), f.width > 1, f.height > 1 else { continue }
                _ = f
                out.append(Win(element: win, app: name, title: title))
            }
        }
        return out
    }

    private func isMinimized(_ win: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &ref)
        return (ref as? Bool) ?? false
    }

    /// True if the window's position is settable via AX — a real, movable
    /// window. Non-movable overlays (menus, popovers) report false.
    private func isMovable(_ win: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let err = AXUIElementIsAttributeSettable(win,
                                                 kAXPositionAttribute as CFString,
                                                 &settable)
        return err == .success && settable.boolValue
    }

    private func frameOf(_ win: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeVal)
        guard let posVal, let sizeVal else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &p),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &ref)
        return ref as? String
    }

    private func identifier(_ win: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXIdentifierAttribute as CFString, &ref)
        return ref as? String
    }

    // MARK: - Cells (balanced grid, normalized)

    /// Balanced edge-to-edge grid, normalized 0..1 (top-left origin, y-down),
    /// NO gaps for any count. Top rows hold `cols` cells; the last row holds
    /// the remainder and widens its cells to fill the row. Cols = ceil(sqrt(n)).
    private func balancedCells(count: Int) -> [CGRect] {
        let cols = max(1, Int(Double(count).squareRoot().rounded(.up)))
        let rows = max(1, Int((Double(count) / Double(cols)).rounded(.up)))
        let rh = 1.0 / Double(rows)
        var cells: [CGRect] = []
        var i = 0
        for r in 0..<rows {
            let isLastRow = r == rows - 1
            let inRow = isLastRow ? (count - i) : cols
            let cw = 1.0 / Double(inRow)
            let y = Double(r) * rh
            for c in 0..<inRow {
                let x = Double(c) * cw
                cells.append(CGRect(x: x, y: y, width: cw, height: rh))
                i += 1
            }
        }
        return cells
    }

    // MARK: - LLM assignment

    /// Ask the text LLM to assign each window to one cell (one-to-one) from
    /// app name + title + cell positions. Returns `result[windowIndex] =
    /// cellIndex`, or nil on any failure (caller falls back to in-order).
    private func assignCells(wins: [Win], cells: [CGRect],
                             hint: String) async -> [Int]? {
        let key = AppSettings.shared.fireworksKey
        guard !key.isEmpty else { return nil }
        let engine = FireworksReasoningLLM(modelId: AppSettings.shared.reasoningModelId,
                                           apiKey: key)

        var wlist = ""
        for (i, w) in wins.enumerated() {
            wlist += "[\(i)] \(w.app) — \"\(w.title)\"\n"
        }
        var clist = ""
        for (i, c) in cells.enumerated() {
            clist += "[\(i)] x=\(fmt(c.origin.x)) y=\(fmt(c.origin.y)) " +
                    "w=\(fmt(c.size.width)) h=\(fmt(c.size.height))\n"
        }
        let pref = hint.isEmpty ? "" : " Preference: \(hint)."
        let prompt = """
        Assign each of \(wins.count) open macOS windows to one of \(cells.count) screen cells, one-to-one (every window gets exactly one cell, every cell used once). Put the most important/active window in the largest or top-left cell; reference/secondary windows elsewhere.\(pref)
        Windows:
        \(wlist)
        Cells (normalized 0..1, origin top-left, y down):
        \(clist)
        Return ONLY JSON: {"assign":[{"window":0,"cell":1}, ...]} covering every window 0..\(wins.count - 1). No prose.
        """

        do {
            let raw = try await engine.reason(prompt: prompt)
            return parseAssign(raw, n: wins.count)
        } catch {
            return nil
        }
    }

    /// Validate the LLM mapping: one-to-one, all window indices 0..n-1 present,
    /// all cell indices unique and in range. Returns nil if invalid.
    private func parseAssign(_ text: String, n: Int) -> [Int]? {
        guard let blob = firstJSONBlob(text),
              let data = blob.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["assign"] as? [[String: Any]] else { return nil }
        var map = Array(repeating: -1, count: n)
        var usedCells: Set<Int> = []
        for item in arr {
            guard let w = item["window"] as? Int, let c = item["cell"] as? Int else { continue }
            guard w >= 0, w < n, c >= 0, c < n else { return nil }
            if map[w] != -1 { return nil }        // duplicate window
            if !usedCells.insert(c).inserted { return nil }  // duplicate cell
            map[w] = c
        }
        return map.contains(-1) ? nil : map
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    // MARK: - Apply

    /// AX-coordinate visible rect (top-left origin of primary display, y-down).
    private func axVisibleFrame(_ screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let totalH = screen.frame.height
        return CGRect(x: vf.origin.x,
                      y: totalH - (vf.origin.y + vf.height),
                      width: vf.width,
                      height: vf.height)
    }

    /// Convert a normalized (top-left, y-down) rect to AX screen points,
    /// integer-snapped so adjacent cells share exact edges (no seams).
    private func axRect(normalized n: CGRect, screen: NSScreen) -> CGRect {
        let v = axVisibleFrame(screen)
        let x = (v.origin.x + n.origin.x * v.width).rounded()
        let y = (v.origin.y + n.origin.y * v.height).rounded()
        let w = (n.size.width * v.width).rounded()
        let h = (n.size.height * v.height).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
    }

    @discardableResult
    private func setWindowFrame(_ el: AXUIElement, _ rect: CGRect) -> Bool {
        var pos = CGPoint(x: rect.origin.x, y: rect.origin.y)
        guard let posVal = AXValueCreate(.cgPoint, &pos) else { return false }
        let r1 = AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, posVal)
        var size = CGSize(width: rect.size.width, height: rect.size.height)
        guard let sizeVal = AXValueCreate(.cgSize, &size) else { return false }
        let r2 = AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeVal)
        return r1 == .success && r2 == .success
    }

    // MARK: - Helpers

    private func firstJSONBlob(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }
}

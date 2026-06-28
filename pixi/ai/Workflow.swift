//
//  Workflow.swift
//  pixi
//
//  A hand-rolled LangGraph-style computer-use agent. State carries goal,
//  history, and MEMORY (facts remembered across turns). Nodes: perceive →
//  reason → execute → memorize → route. The reason node (vision LLM) sees
//  the screenshot + AX + manifest + history + memory, returns one action
//  AND optional memory updates. Route: done / max-steps / loop.
//
//  Both Option+K (typed) and Option+Space (voice) feed a prompt here.
//
//  Created by Girith Choudhary on 6/24/26.
//

import AppKit
import CoreGraphics

@MainActor
final class WorkflowController {
    static let shared = WorkflowController()

    enum Source { case typed, voice }

    private let maxSteps = 12

    /// Per-interaction control flags, set from the UI. The run loop honors
    /// these between iterations: abort stops the run; pause holds it.
    private var aborts: Set<UUID> = []
    private var paused: Set<UUID> = []

    private init() {}

    /// User requested stop — the run loop exits at the next iteration boundary.
    func stop(_ id: UUID) { aborts.insert(id) }

    /// User toggled pause. While paused, the loop sleeps without acting.
    func pause(_ id: UUID) {
        paused.insert(id)
        AITrace.shared.setPaused(id: id, true)
    }

    /// User resumed a paused run.
    func resume(_ id: UUID) {
        paused.remove(id)
        AITrace.shared.setPaused(id: id, false)
    }

    // MARK: - Graph state

    struct State {
        let goal: String
        var history: [String] = []
        var memory: [String] = []
        var step: Int = 0
        var done: Bool = false
        var screenshot: CGImage?
        var screenFrame: CGRect = .zero
        var ax: String = ""
    }

    func run(prompt: String, source: Source, interactionId: UUID? = nil) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let title = source == .voice ? "Voice command" : "Typed command"
        let symbol = source == .voice ? "waveform" : "keyboard"
        let id = interactionId
            ?? AITrace.shared.begin(title: title, subtitle: trimmed, symbol: symbol)
        AITrace.shared.setRunning(id: id)

        let engine = FireworksVisionLLM(modelId: AppSettings.shared.visionModelId,
                                        apiKey: AppSettings.shared.fireworksKey)

        // Memory is per-interaction only — does NOT carry across runs.
        var state = State(goal: trimmed)
        var lastKey: String? = nil   // loop detection: immediate back-to-back repeat

        // Drive the graph.
        while !state.done && state.step < maxSteps {
            // User controls: abort stops; pause holds without acting.
            if aborts.contains(id) {
                aborts.remove(id)
                paused.remove(id)
                AITrace.shared.addStep(to: id, kind: .tool, label: "stopped",
                                       input: "", output: "aborted by user",
                                       status: .failed, durationMs: 0,
                                       group: state.step)
                AITrace.shared.complete(id: id, status: .failed, output: "aborted by user")
                return
            }
            while paused.contains(id) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if aborts.contains(id) { break }
            }
            if aborts.contains(id) { continue }

            state.step &+= 1

            // perceive
            await perceive(&state, id: id)
            guard state.screenshot != nil else {
                AITrace.shared.complete(id: id, status: .failed, output: "capture failed")
                return
            }

            // reason (vision LLM) → action + memory updates
            let raw: String
            do {
                raw = try await engine.analyze(imageData: resizedPNG(state.screenshot!, maxDim: 1280),
                                               prompt: buildPrompt(state: state))
            } catch {
                AITrace.shared.addStep(to: id, kind: .vision,
                                       label: "Vision (\(AppSettings.shared.visionLlm))",
                                       input: "step \(state.step)", output: "\(error)",
                                       status: .failed, durationMs: 0,
                                       group: state.step)
                AITrace.shared.complete(id: id, status: .failed, output: "\(error)")
                return
            }
            let t = Date()
            AITrace.shared.addStep(to: id, kind: .vision,
                                   label: "Vision (\(AppSettings.shared.visionLlm))",
                                   input: "step \(state.step)",
                                   output: String(raw.prefix(240)),
                                   status: .success, durationMs: ms(t),
                                   group: state.step, detail: raw)

            guard let (actions, memUpdates, achieved) = parseActions(raw) else {
                AITrace.shared.complete(id: id, status: .failed,
                                        output: "unparseable: \(raw.prefix(200))")
                return
            }

            // memorize (before execute so memory persists even if an action fails)
            for m in memUpdates where !state.memory.contains(m) {
                state.memory.append(m)
            }
            if !memUpdates.isEmpty {
                AITrace.shared.addStep(to: id, kind: .tool,
                                       label: "memory",
                                       input: memUpdates.joined(separator: "; "),
                                       output: "\(state.memory.count) facts",
                                       status: .success, durationMs: 0,
                                       group: state.step,
                                       detail: state.memory.joined(separator: "\n"))
            }

            // Pre-check from the same vision call: the model claims the goal
            // is achieved. Don't trust it — run ONE dedicated vision verify on
            // a fresh full-screen capture (no crop, so it sees the target app
            // even if focus drifted). This is the N+1 call: only fires when
            // completion is claimed, not every step.
            if achieved {
                let verified = await verify(goal: state.goal, engine: engine, id: id,
                                            group: state.step)
                if verified == true {
                    _ = await ToolRegistry.dispatch(name: "done", args: [:], interactionId: id,
                                                    group: state.step)
                    state.done = true
                    break
                } else {
                    // Model claimed done but vision says otherwise — keep going.
                    state.history.append("verify: goal NOT achieved — continue")
                    AITrace.shared.addStep(to: id, kind: .tool,
                                           label: "verify rejected done",
                                           input: state.goal,
                                           output: "goal not achieved on screen — continuing",
                                           status: .failed, durationMs: 0,
                                           group: state.step)
                }
            }

            guard !actions.isEmpty else {
                AITrace.shared.addStep(to: id, kind: .tool,
                                       label: "no actions",
                                       input: "",
                                       output: "achieved=false but no actions — continuing",
                                       status: .failed, durationMs: 0,
                                       group: state.step)
                continue
            }

            // Execute the batch of actions in order WITHOUT re-perceiving
            // between them (the next turn re-sees the screen).
            // Immediate-repeat loop detection applies across consecutive actions.
            for (toolName, toolArgs) in actions {
                if toolName == "done" {
                    // Model emitted done but didn't set achieved — trust it
                    // only if it also set achieved; otherwise ignore and keep
                    // going (the pre-check is authoritative).
                    break
                }
                let key = "\(toolName)|\(argsKey(toolArgs))"
                if let last = lastKey, last == key {
                    AITrace.shared.addStep(to: id, kind: .tool,
                                           label: "loop detected",
                                           input: key,
                                           output: "repeated the last action — stopping",
                                           status: .failed, durationMs: 0,
                                           group: state.step)
                    state.done = true
                    break
                }
                let result = await ToolRegistry.dispatch(name: toolName, args: toolArgs,
                                                         interactionId: id,
                                                         group: state.step)
                state.history.append("\(toolName)(\(toolArgs)) → \(result.ok ? result.output : result.error ?? "failed")")
                lastKey = result.ok ? key : nil
            }
            if state.done { break }

            // checkpoint: persist a state snapshot for this thread/step.
            JSONFileCheckpointer.shared.save(CheckpointSnapshot(
                threadId: id, step: state.step, goal: state.goal,
                history: state.history, memory: state.memory,
                done: state.done, savedAt: Date().timeIntervalSince1970))
        }

        let outcome = state.done ? "done" : "max steps reached"
        AITrace.shared.complete(id: id,
                                status: .success,
                                output: "\(outcome) — memory: \(state.memory.count) facts")
        aborts.remove(id)
        paused.remove(id)

        // Final checkpoint (per-thread; not shared across interactions).
        JSONFileCheckpointer.shared.save(CheckpointSnapshot(
            threadId: id, step: state.step, goal: state.goal,
            history: state.history, memory: state.memory,
            done: state.done, savedAt: Date().timeIntervalSince1970))
    }

    // MARK: - Nodes

    /// Verify node: re-capture the FULL screen and ask the vision LLM whether
    /// the goal is achieved. Used only when the reason call claims achieved —
    /// a dedicated check so the model can't self-certify a wrong completion.
    /// Full-screen (no frontmost crop) so it sees the target app even if focus
    /// drifted. Returns nil if the check itself fails (treat as not yet).
    private func verify(goal: String, engine: FireworksVisionLLM, id: UUID,
                        group: Int) async -> Bool? {
        guard let (cg, _) = await ScreenCapture.captureMainScreen() else { return nil }
        let t0 = Date()
        let prompt = "Goal: \(goal). Look at this screenshot carefully. Has the goal " +
            "actually been achieved and visible on screen right now? Do NOT infer from " +
            "past actions — only what is visible. " +
            "Respond with ONLY JSON: {\"achieved\": true|false, \"reason\": \"...\"}."
        do {
            let raw = try await engine.analyze(imageData: resizedPNG(cg, maxDim: 1280),
                                               prompt: prompt)
            let achieved = parseAchieved(raw)
            AITrace.shared.addStep(to: id, kind: .vision,
                                   label: "verify",
                                   input: goal,
                                   output: "\(achieved) | \(raw.prefix(160))",
                                   status: .success, durationMs: ms(t0),
                                   group: group, detail: raw)
            return achieved
        } catch {
            AITrace.shared.addStep(to: id, kind: .vision,
                                   label: "verify", input: goal,
                                   output: "\(error)", status: .failed, durationMs: ms(t0),
                                   group: group)
            return nil
        }
    }

    private func parseAchieved(_ text: String) -> Bool {
        guard let blob = firstJSONBlob(text),
              let data = blob.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["achieved"] as? Bool) ?? false
    }

    /// perceive: capture screen + AX snapshot.
    private func perceive(_ state: inout State, id: UUID) async {
        let t0 = Date()
        guard let (cg, frame) = await ScreenCapture.captureMainScreen() else {
            AITrace.shared.addStep(to: id, kind: .tool, label: "Screen capture",
                                   input: "", output: "no screen / permission denied",
                                   status: .failed, durationMs: ms(t0))
            return
        }
        state.screenshot = cg
        state.screenFrame = frame
        state.ax = AccessibilityTree.snapshotFrontmost()

        AITrace.shared.attachMedia(id: id,
                                   screenshot: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)),
                                   targets: [], frame: frame)
        // Record the AX snapshot every iteration so each step card carries
        // its own tree; full text lives in `detail` for copy/expand.
        AITrace.shared.addStep(to: id, kind: .tool,
                               label: state.ax.isEmpty ? "Accessibility (unavailable)" : "Accessibility tree",
                               input: "",
                               output: state.ax.isEmpty ? "not trusted" : "\(state.ax.count) chars",
                               status: state.ax.isEmpty ? .failed : .success,
                               durationMs: ms(t0),
                               group: state.step,
                               detail: state.ax)
    }

    // MARK: - Prompt + parse

    private func buildPrompt(state: State) -> String {
        var p = "You are a computer-use agent that drives macOS like a human: you see this screenshot and pick ONE next action.\n\n"
        p += "User goal: \(state.goal)\n\n"
        p += "Available actions:\n\(ToolRegistry.manifest)\n\n"
        p += "Coord for click normalized 0..1 from image TOP-LEFT. Ground click coords yourself from the screenshot — do NOT call vision_click. Rule: if the goal involves an app, call list_apps FIRST — never assume an app is installed from icons/screenshots. Each tool's description (call list_tools if unsure) says when to use it. Don't repeat an action that already failed — change approach. Don't redo an action that already succeeded (e.g. if you pressed return to submit a search, do NOT type the query again — click a result). DEFAULT: 'rearrange/organize/tidy/tile tabs/windows/apps' means tiling app WINDOWS across the screen — call arrange_windows. Only treat 'tabs' as in-app browser tab reorder if the user explicitly names ONE app's tabs (e.g. 'rearrange Safari's tabs') — and no tool does that, so say so instead of hand-writing AppleScript.\n\n"
        if !state.ax.isEmpty {
            p += "AX tree (role \"title\" [x y w h]):\n\(state.ax)\n\n"
        } else {
            p += "AX tree unavailable.\n\n"
        }
        if !state.memory.isEmpty {
            p += "Memory (facts remembered across turns):\n"
            for m in state.memory { p += "- \(m)\n" }
            p += "\n"
        }
        if !state.history.isEmpty {
            p += "Previous actions:\n"
            for h in state.history { p += "- \(h)\n" }
            p += "\n"
        }
        p += "Respond with ONLY JSON, first char '{', last '}':\n"
        p += "{\"achieved\": <true|false>, \"actions\": [{\"tool\": \"<action>\", \"args\": {<keys>}}, ...], \"memory\": [\"<short fact>\", ...]}\n"
        p += "This single response does BOTH: (1) pre-check — set achieved:true ONLY if the goal is visibly achieved on the current screenshot; (2) next steps — if achieved is false, give the actions to progress the goal. If achieved is true, actions may be [] (the task ends). Try to group as many actions as possible into one turn. memory = new facts worth keeping; omit or [] if nothing new.\n"
        p += "If goal achieved: {\"achieved\": true, \"actions\": [], \"memory\": [...]}"
        return p
    }

    /// Parse the model response into actions + memory + achieved flag.
    /// One vision call per step does BOTH the goal pre-check and the next
    /// actions: `achieved:true` ends the task, `achieved:false` runs actions.
    /// Accepts `{"achieved":bool, "actions":[...], "memory":[...]}` or the
    /// single-action shape `{"tool":...,"args":...,"memory":[...]}`.
    private func parseActions(_ text: String) -> ([(String, [String: Any])], [String], Bool)? {
        guard let blob = firstJSONBlob(text),
              let data = blob.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let mem = (obj["memory"] as? [String]) ?? []
        let achieved = (obj["achieved"] as? Bool) ?? false
        if let arr = obj["actions"] as? [[String: Any]] {
            let acts = arr.compactMap { item -> (String, [String: Any])? in
                guard let tool = item["tool"] as? String else { return nil }
                return (tool, (item["args"] as? [String: Any]) ?? [:])
            }
            return (acts, mem, achieved)
        }
        if let tool = obj["tool"] as? String {
            let args = (obj["args"] as? [String: Any]) ?? [:]
            return ([(tool, args)], mem, achieved)
        }
        return nil
    }

    private func firstJSONBlob(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }

    private func argsKey(_ args: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args,
                                                     options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private func pngData(_ cg: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Downscaled PNG for the vision call — full-retina screenshots are
    /// huge and slow to infer on. maxDim caps the longest side; aspect kept.
    private func resizedPNG(_ cg: CGImage, maxDim: CGFloat) -> Data {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDim / max(w, h))
        let nw = max(1, Int(w * scale)), nh = max(1, Int(h * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: nw, pixelsHigh: nh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            return pngData(cg)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: cg, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: nw, height: nh))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? pngData(cg)
    }

    private func ms(_ since: Date) -> Int {
        Int(Date().timeIntervalSince(since) * 1000)
    }
}

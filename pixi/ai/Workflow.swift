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

    private init() {}

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

        let engine = FireworksVisionLLM(modelId: AppSettings.shared.visionModelId,
                                        apiKey: AppSettings.shared.fireworksKey)

        // Memory is per-interaction only — does NOT carry across runs.
        var state = State(goal: trimmed)
        var lastKey: String? = nil   // loop detection: immediate back-to-back repeat

        // Drive the graph.
        while !state.done && state.step < maxSteps {
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
                                       status: .failed, durationMs: 0)
                AITrace.shared.complete(id: id, status: .failed, output: "\(error)")
                return
            }
            let t = Date()
            AITrace.shared.addStep(to: id, kind: .vision,
                                   label: "Vision (\(AppSettings.shared.visionLlm))",
                                   input: "step \(state.step)",
                                   output: String(raw.prefix(240)),
                                   status: .success, durationMs: ms(t))

            guard let (actions, memUpdates) = parseActions(raw), !actions.isEmpty else {
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
                                       status: .success, durationMs: 0)
            }

            // Execute the batch of actions in order WITHOUT re-perceiving
            // between them (the next turn re-sees the screen). `done` in the
            // batch stops after the current action. Immediate-repeat loop
            // detection applies across consecutive actions in the batch.
            for (toolName, toolArgs) in actions {
                if toolName == "done" {
                    _ = await ToolRegistry.dispatch(name: "done", args: [:], interactionId: id)
                    state.done = true
                    break
                }
                let key = "\(toolName)|\(argsKey(toolArgs))"
                if let last = lastKey, last == key {
                    AITrace.shared.addStep(to: id, kind: .tool,
                                           label: "loop detected",
                                           input: key,
                                           output: "repeated the last action — stopping",
                                           status: .failed, durationMs: 0)
                    state.done = true
                    break
                }
                let result = await ToolRegistry.dispatch(name: toolName, args: toolArgs,
                                                         interactionId: id)
                state.history.append("\(toolName)(\(toolArgs)) → \(result.ok ? result.output : result.error ?? "failed")")
                lastKey = result.ok ? key : nil
            }

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

        // Final checkpoint (per-thread; not shared across interactions).
        JSONFileCheckpointer.shared.save(CheckpointSnapshot(
            threadId: id, step: state.step, goal: state.goal,
            history: state.history, memory: state.memory,
            done: state.done, savedAt: Date().timeIntervalSince1970))
    }

    // MARK: - Nodes

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
        if state.step == 1 {
            AITrace.shared.addStep(to: id, kind: .tool,
                                   label: state.ax.isEmpty ? "Accessibility (unavailable)" : "Accessibility tree",
                                   input: "",
                                   output: state.ax.isEmpty ? "not trusted" : "\(state.ax.count) chars",
                                   status: state.ax.isEmpty ? .failed : .success,
                                   durationMs: ms(t0))
        }
    }

    // MARK: - Prompt + parse

    private func buildPrompt(state: State) -> String {
        var p = "You are a computer-use agent that drives macOS like a human: you see this screenshot and pick ONE next action.\n\n"
        p += "User goal: \(state.goal)\n\n"
        p += "Available actions:\n\(ToolRegistry.manifest)\n\n"
        p += "Coord for click normalized 0..1 from image TOP-LEFT. Rule: if the goal involves an app, call list_apps FIRST — never assume an app is installed from icons/screenshots. Each tool's description (call list_tools if unsure) says when to use it. Don't repeat an action that already failed — change approach. Don't redo an action that already succeeded (e.g. if you pressed return to submit a search, do NOT type the query again — click a result or call done). If the goal is a search and the search is submitted/loaded, call done.\n\n"
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
        p += "{\"actions\": [{\"tool\": \"<action>\", \"args\": {<keys>}}, ...], \"memory\": [\"<short fact>\", ...]}\n"
        p += "Try to group as many actions as possible into one turn. `done` as an action ends the task. memory = new facts worth keeping; omit or [] if nothing new.\n"
        p += "If goal achieved: {\"actions\": [{\"tool\": \"done\", \"args\": {}}]}"
        return p
    }

    /// Parse the model response into a batch of actions + memory updates.
    /// Accepts `{"actions":[{"tool":...,"args":...}, ...], "memory":[...]}`
    /// or the single-action shape `{"tool":...,"args":...,"memory":[...]}`.
    private func parseActions(_ text: String) -> ([(String, [String: Any])], [String])? {
        guard let blob = firstJSONBlob(text),
              let data = blob.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let mem = (obj["memory"] as? [String]) ?? []
        if let arr = obj["actions"] as? [[String: Any]] {
            let acts = arr.compactMap { item -> (String, [String: Any])? in
                guard let tool = item["tool"] as? String else { return nil }
                return (tool, (item["args"] as? [String: Any]) ?? [:])
            }
            return (acts, mem)
        }
        if let tool = obj["tool"] as? String {
            let args = (obj["args"] as? [String: Any]) ?? [:]
            return ([(tool, args)], mem)
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

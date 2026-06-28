//
//  AITrace.swift
//  pixi
//
//  Shared chain/trace store. Every workflow step (STT, vision, reasoning)
//  is recorded here so the Interactions compartment can render observability
//  into what the platform did, in order, with latency + status.
//
//  Created by Girith Choudhary on 6/24/26.
//

import SwiftUI
import Combine
import AppKit
import CoreGraphics

final class AITrace: ObservableObject {
    static let shared = AITrace()

    @Published private(set) var interactions: [Interaction] = []

    private init() {}

    /// Begin a new interaction chain. Returns the id to pass to `addStep`.
    @discardableResult
    func begin(title: String, subtitle: String, symbol: String) -> UUID {
        let item = Interaction(title: title, subtitle: subtitle, symbol: symbol)
        interactions.insert(item, at: 0)
        return item.id
    }

    /// Append a workflow step to an existing interaction. `group` is the
    /// agent iteration index (state.step) — steps sharing a group render as
    /// one combined card (AX → vision → memory → tools). `detail` holds the
    /// full log content (AX tree text, raw vision response) for copy/expand;
    /// `output` stays a short display label.
    func addStep(to id: UUID,
                 kind: Step.Kind,
                 label: String,
                 input: String,
                 output: String = "",
                 status: Step.Status = .pending,
                 durationMs: Int = 0,
                 group: Int = 0,
                 detail: String = "") {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        let step = Step(kind: kind, label: label, input: input,
                        output: output, status: status, durationMs: durationMs,
                        group: group, detail: detail)
        interactions[idx].steps.append(step)
        interactions[idx].subtitle = step.label
    }

    /// Mark an interaction's final outcome.
    func complete(id: UUID, status: Step.Status, output: String) {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        interactions[idx].status = status
        interactions[idx].output = output
        interactions[idx].paused = false
    }

    /// Mark an interaction as actively running (shows Stop/Pause controls).
    func setRunning(id: UUID) {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        interactions[idx].status = .running
    }

    /// Toggle the paused flag (drives Pause/Resume label + loop wait).
    func setPaused(id: UUID, _ paused: Bool) {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        interactions[idx].paused = paused
    }

    /// Update an interaction's subtitle (e.g. the final transcript).
    func updateSubtitle(id: UUID, _ subtitle: String) {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        interactions[idx].subtitle = subtitle
    }

    /// Attach the captured screenshot + parsed targets so the Interactions
    /// detail can render the overlay inline for inspection.
    func attachMedia(id: UUID, screenshot: NSImage, targets: [Target], frame: CGRect) {
        guard let idx = interactions.firstIndex(where: { $0.id == id }) else { return }
        interactions[idx].screenshot = screenshot
        interactions[idx].targets = targets
        interactions[idx].screenFrame = frame
    }

    struct Interaction: Identifiable {
        let id = UUID()
        let title: String
        var subtitle: String
        let symbol: String
        var steps: [Step] = []
        var status: Step.Status = .pending
        var output: String = ""
        var paused: Bool = false

        // Inspect-only media for the Interactions detail view.
        var screenshot: NSImage?
        var targets: [Target]?
        var screenFrame: CGRect = .zero

        var timeLabel: String { "Just now" } // TODO: real relative timestamps.
    }

    struct Step: Identifiable {
        let id = UUID()
        let kind: Kind
        let label: String
        let input: String
        var output: String
        var status: Status
        let durationMs: Int
        /// Agent iteration index — groups sub-steps into one card.
        let group: Int
        /// Full log content (AX tree, raw vision response) for copy/expand.
        let detail: String

        enum Kind { case stt, vision, reasoning, tts, tool }
        enum Status { case pending, running, success, failed }
    }
}

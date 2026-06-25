//
//  Checkpointer.swift
//  pixi
//
//  LangGraph-style short-term memory: a checkpointer saves a snapshot of
//  the graph State after each step, keyed by thread_id (= interaction id).
//  JSON-file backed. Enables resuming / inspecting a thread's state evolution.
//  The screenshot/AX are ephemeral and excluded from the snapshot.
//
//  Created by Girith Choudhary on 6/25/26.
//

import Foundation

/// Codable snapshot of the graph state at a step (excludes ephemeral media).
struct CheckpointSnapshot: Codable {
    let threadId: UUID
    let step: Int
    let goal: String
    let history: [String]
    let memory: [String]
    let done: Bool
    let savedAt: Double
}

@MainActor
protocol Checkpointer {
    func save(_ snapshot: CheckpointSnapshot)
    func latest(threadId: UUID) -> CheckpointSnapshot?
    func steps(threadId: UUID) -> [CheckpointSnapshot]
}

/// JSON-file backed checkpointer: <AppSupport>/pixi/checkpoints.json.
@MainActor
final class JSONFileCheckpointer: Checkpointer {
    static let shared = JSONFileCheckpointer()

    private var byThread: [UUID: [CheckpointSnapshot]] = [:]
    private let url: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("pixi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("checkpoints.json")
        load()
    }

    func save(_ snapshot: CheckpointSnapshot) {
        byThread[snapshot.threadId, default: []].append(snapshot)
        save()
    }

    func latest(threadId: UUID) -> CheckpointSnapshot? {
        byThread[threadId]?.last
    }

    func steps(threadId: UUID) -> [CheckpointSnapshot] {
        byThread[threadId] ?? []
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([CheckpointSnapshot].self, from: data) else {
            return
        }
        for s in arr { byThread[s.threadId, default: []].append(s) }
    }

    private func save() {
        let all = Array(byThread.values.flatMap { $0 })
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

//
//  AppSettings.swift
//  pixi
//
//  Persisted, app-wide settings. Engines + WorkflowController read the
//  current model selections + API keys from here (not the per-view @State
//  in SettingsView). Selections are @AppStorage (UserDefaults); keys are
//  Keychain-backed via KeychainStore.
//
//  Created by Girith Choudhary on 6/24/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Model display names (what the Settings picker shows).
    @AppStorage("stt") var stt: String = "gpt-4o-transcribe"
    @AppStorage("visionLlm") var visionLlm: String = "Qwen 3.7 Plus"
    @AppStorage("llm") var llm: String = "Qwen 3.7 Plus"

    private init() {}

    // API keys live in Keychain.
    var fireworksKey: String { KeychainStore.get(KeychainStore.Account.fireworks) ?? "" }
    var openaiKey: String { KeychainStore.get(KeychainStore.Account.openai) ?? "" }

    /// Resolved Fireworks model id for the vision selection.
    var visionModelId: String { FireworksModels.id(for: visionLlm) }
    /// Resolved Fireworks model id for the reasoning selection.
    var reasoningModelId: String { FireworksModels.id(for: llm) }
}

/// Maps the human-readable model names shown in Settings to the Fireworks
/// API model ids used in chat-completions calls.
enum FireworksModels {
    static let visionOptions = ["Qwen 3.7 Plus", "Kimi k2.7 code", "Minimax M3"]
    static let reasoningOptions = ["Qwen 3.7 Plus", "Kimi k2.7 code", "Minimax M3", "GLM 5.2"]

    private static let map: [String: String] = [
        "Qwen 3.7 Plus": "fireworks/qwen3p7-plus",
        "Kimi k2.7 code": "fireworks/kimi-k2p7-code",
        "Minimax M3": "fireworks/minimax-m3",
        "GLM 5.2": "fireworks/glm-5p2"
    ]

    static func id(for displayName: String) -> String {
        map[displayName] ?? "fireworks/qwen3p7-plus"
    }
}

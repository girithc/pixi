//
//  VisionLLM.swift
//  pixi
//
//  Vision LLM via Fireworks AI (default fireworks/qwen3p7-plus). Sends a
//  screenshot + a goal-directed grounding prompt and returns the raw model
//  text; the caller parses Targets out of it. Pure transport — tracing is
//  owned by WorkflowController.
//
//  Created by Girith Choudhary on 6/24/26.
//

import Foundation

@MainActor
protocol VisionLLMEngine {
    func analyze(imageData: Data, prompt: String) async throws -> String
}

/// Fireworks vision LLM via the chat completions API (image content part).
@MainActor
final class FireworksVisionLLM: VisionLLMEngine {
    private let modelId: String
    private let apiKey: String
    private let endpoint = URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!

    init(modelId: String, apiKey: String) {
        self.modelId = modelId
        self.apiKey = apiKey
    }

    func analyze(imageData: Data, prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw EngineError.missingKey("Fireworks") }

        let b64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "model": modelId,
            "temperature": 0,
            "max_tokens": 4000,
            "messages": [
                ["role": "system",
                 "content": "You are a macOS computer-use agent. Respond with ONLY a JSON object — no prose, no reasoning, no markdown, no code fences. The first character must be '{' and the last must be '}'."],
                ["role": "user",
                 "content": [
                    ["type": "image_url",
                     "image_url": ["url": "data:image/png;base64,\(b64)"]],
                    ["type": "text", "text": prompt]
                ]]
            ]
        ]

        let raw = try await post(body)
        return try content(from: raw)
    }

    // MARK: - Transport

    private func post(_ body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func content(from data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw EngineError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }
}

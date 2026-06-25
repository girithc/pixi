//
//  ReasoningLLM.swift
//  pixi
//
//  Reasoning LLM via Fireworks AI (text-only chat completions). Transport
//  wired and ready; not invoked by the v1 capture→vision→overlay workflow.
//  Tracing owned by WorkflowController.
//
//  Created by Girith Choudhary on 6/24/26.
//

import Foundation

@MainActor
protocol ReasoningLLMEngine {
    func reason(prompt: String) async throws -> String
}

/// Fireworks reasoning LLM via the chat completions API.
@MainActor
final class FireworksReasoningLLM: ReasoningLLMEngine {
    private let modelId: String
    private let apiKey: String
    private let endpoint = URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!

    init(modelId: String, apiKey: String) {
        self.modelId = modelId
        self.apiKey = apiKey
    }

    func reason(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw EngineError.missingKey("Fireworks") }
        // Tool routing needs a short JSON answer fast: minimize reasoning,
        // cap output, deterministic. reasoning_effort=low cuts the long
        // "thinking" phase that made calls take ~40s.
        let body: [String: Any] = [
            "model": modelId,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0,
            "max_tokens": 512,
            "reasoning_effort": "low"
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw EngineError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }
}

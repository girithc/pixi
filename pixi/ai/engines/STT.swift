//
//  STT.swift
//  pixi
//
//  Speech-to-text (batch) via OpenAI. We capture audio while listening, then
//  send the recording on Enter. Default model: gpt-4o-transcribe; fallback:
//  gpt-4o-mini-transcribe. Pure transport — tracing owned by WorkflowController.
//
//  Created by Girith Choudhary on 6/24/26.
//

import Foundation

@MainActor
protocol STTEngine {
    func transcribe(audioURL: URL) async throws -> String
}

/// OpenAI batch transcription via the Audio API (multipart form).
@MainActor
final class OpenAISTT: STTEngine {
    private let model: String
    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(model: String, apiKey: String) {
        self.model = model
        self.apiKey = apiKey
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw EngineError.missingKey("OpenAI") }
        let audio = try Data(contentsOf: audioURL)

        let boundary = "pixi-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = multipart(boundary: boundary, audio: audio,
                                 filename: audioURL.lastPathComponent)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EngineError.badStatus(String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            throw EngineError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }

    private func multipart(boundary: String, audio: Data, filename: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)")
        append("\(model)\(crlf)")

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(crlf)")
        append("Content-Type: audio/m4a\(crlf)\(crlf)")
        body.append(audio)
        append(crlf)
        append("--\(boundary)--\(crlf)")
        return body
    }
}

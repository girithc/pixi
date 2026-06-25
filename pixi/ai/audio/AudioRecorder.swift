//
//  AudioRecorder.swift
//  pixi
//
//  Mic capture for the voice path (Option+Space). AVAudioEngine taps the
//  input and writes PCM to a temp .caf; on stop returns the file URL for
//  OpenAI batch transcription. Requires microphone TCC (Permissions.listening).
//
//  Created by Girith Choudhary on 6/24/26.
//

import AVFoundation

@MainActor
final class AudioRecorder {
    static let shared = AudioRecorder()

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var url: URL?

    private init() {}

    var isRecording: Bool { engine.isRunning }

    func start() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixi-\(UUID().uuidString).caf")
        url = tmp
        file = try AVAudioFile(forWriting: tmp, settings: format.settings)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> URL? {
        guard engine.isRunning else { return url }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        return url
    }
}

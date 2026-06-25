//
//  Permissions.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Combine

@MainActor
final class Permissions: ObservableObject {
    @Published var screenCapture = false
    @Published var computerUse = false
    @Published var listening = false

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        screenCapture = CGPreflightScreenCaptureAccess()
        computerUse = AXIsProcessTrusted()
        listening = AVAudioApplication.shared.recordPermission == .granted
    }

    func requestScreenCapture() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        openSettings("Privacy_ScreenCapture")
    }

    func requestComputerUse() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openSettings("Privacy_Accessibility")
    }

    func requestListening() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            // System shows the TCC prompt; app appears in the list
            // only after a decision is recorded, so don't jump to Settings yet.
            AVAudioApplication.requestRecordPermission { _ in
                Task { @MainActor in self.refresh() }
            }
        case .denied:
            // macOS won't re-prompt once denied — point user at Settings.
            openSettings("Privacy_Microphone")
        case .granted:
            break
        @unknown default:
            openSettings("Privacy_Microphone")
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

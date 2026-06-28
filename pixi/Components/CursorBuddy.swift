//
//  CursorBuddy.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI
import AppKit
import CoreVideo
import Carbon

@MainActor
final class CursorBuddy {
    static let shared = CursorBuddy()

    private var panel: NSPanel?
    private var star: NSImageView?
    private var waveformHost: NSHostingView<WaveformView>?
    private var link: CVDisplayLink?
    private var screen: NSScreen?
    private var current = CGPoint.zero

    private let size: CGFloat = 20
    /// Padding around the triangle so the glow has room to spread.
    private let glow: CGFloat = 14
    private var canvas: CGFloat { size + glow * 2 }
    private let waveSize: CGFloat = 44
    private let ease: CGFloat = 0.08

    /// When true the buddy shows audio-waveform glyph to signal listen mode.
    private(set) var isListening = false

    private let returnHotkeyID: UInt32 = 3

    func start() {
        guard panel == nil else { return }
        makePanel()
        startDisplayLink()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.orderFrontRegardless() }
        }
    }

    private func makePanel() {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.identifier = NSUserInterfaceItemIdentifier("pixi.cursorbuddy")
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true

        let star = NSImageView(frame: NSRect(x: 0, y: 0, width: canvas, height: canvas))
        star.image = sharpTriangleImage(size: size, glow: glow, color: Self.teal)
        // Positive rotation = counterclockwise = apex leans left.
        star.frameRotation = 30
        p.contentView?.addSubview(star)

        // Live, open-concept waveform (no enclosing circle) shown in listen mode.
        let wave = NSHostingView(rootView: WaveformView(color: Self.teal))
        wave.frame = NSRect(x: 0, y: 0, width: waveSize, height: waveSize)
        wave.isHidden = true
        p.contentView?.addSubview(wave)

        p.orderFrontRegardless()
        panel = p
        self.star = star
        self.waveformHost = wave
    }

    private static let teal = NSColor(srgbRed: 0.25, green: 0.88, blue: 0.81,
                                      alpha: 1.0)

    /// Sharp (unrounded) filled equilateral triangle, apex up, with a
    /// soft outer glow in the same color. Drawn directly so corners stay
    /// crisp — SF Symbol's `triangle.fill` is always rounded.
    private func sharpTriangleImage(size: CGFloat, glow: CGFloat, color: NSColor) -> NSImage {
        let canvas = size + glow * 2
        let img = NSImage(size: NSSize(width: canvas, height: canvas))
        img.lockFocus()
        let path = NSBezierPath()
        // Equilateral: side = base. Height = side * √3/2.
        let side = size * 0.7
        let th = side * sqrt(3) / 2
        let tw = side
        let cx = canvas / 2, cy = canvas / 2
        path.move(to: NSPoint(x: cx, y: cy + th / 2))
        path.line(to: NSPoint(x: cx + tw / 2, y: cy - th / 2))
        path.line(to: NSPoint(x: cx - tw / 2, y: cy - th / 2))
        path.close()

        // Colored highlight glow: same hue, zero offset, blur = glow pad.
        // Translucent shadow color so the halo reads soft, not solid.
        // Draw the path twice so the halo spreads further and reads brighter.
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setShadow(offset: .zero, blur: glow,
                          color: color.withAlphaComponent(0.4).cgColor)
        }
        color.setFill()
        path.fill()
        // Second pass: same shadow stacks on top, thickening the spread.
        path.fill()
        img.unlockFocus()
        return img
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnSuccess }
            let buddy = Unmanaged<CursorBuddy>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { buddy.tick() }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link!, callback, ctx)
        CVDisplayLinkStart(link!)
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening else { return }
        isListening = true
        applySymbol()
        // Begin mic capture for the voice path.
        try? AudioRecorder.shared.start()
        // Grab Return globally only while listening so Enter stays
        // normal the rest of the time. Enter stops listen mode.
        HotkeyManager.shared.register(
            keyCode: kVK_Return,
            modifiers: 0,
            id: returnHotkeyID
        ) { [weak self] in self?.stopListening() }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        applySymbol()
        HotkeyManager.shared.unregister(id: returnHotkeyID)

        // Stop mic → transcribe → run the same vision workflow.
        let url = AudioRecorder.shared.stop()
        let id = AITrace.shared.begin(title: "Voice command",
                                      subtitle: "Transcribing…",
                                      symbol: "waveform")
        Task { @MainActor in
            guard let url else {
                AITrace.shared.complete(id: id, status: .failed,
                                        output: "no audio captured")
                return
            }
            let stt = OpenAISTT(model: AppSettings.shared.stt,
                                apiKey: AppSettings.shared.openaiKey)
            let t0 = Date()
            do {
                let text = try await stt.transcribe(audioURL: url)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                AITrace.shared.addStep(to: id, kind: .stt,
                                       label: "Transcribed (\(AppSettings.shared.stt))",
                                       input: url.lastPathComponent,
                                       output: trimmed,
                                       status: trimmed.isEmpty ? .failed : .success,
                                       durationMs: Int(Date().timeIntervalSince(t0) * 1000))
                guard !trimmed.isEmpty else {
                    AITrace.shared.complete(id: id, status: .failed,
                                            output: "empty transcript")
                    return
                }
                AITrace.shared.updateSubtitle(id: id, trimmed)
                // Continue the same chain: capture → ax → vision → overlay.
                await WorkflowController.shared.run(prompt: trimmed,
                                                    source: .voice,
                                                    interactionId: id)
            } catch {
                AITrace.shared.addStep(to: id, kind: .stt,
                                       label: "Transcription failed",
                                       input: url.lastPathComponent,
                                       output: "\(error)", status: .failed,
                                       durationMs: Int(Date().timeIntervalSince(t0) * 1000))
                AITrace.shared.complete(id: id, status: .failed, output: "\(error)")
            }
        }
    }

    /// Swap the cursor glyph between the idle triangle and the
    /// live audio-waveform (open bars, no container).
    private func applySymbol() {
        star?.isHidden = isListening
        waveformHost?.isHidden = !isListening
    }

    private func tick() {
        let m = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(m) }) else { return }
        if s !== screen {
            screen = s
            panel?.setFrame(s.frame, display: true)
        }
        let tx = m.x - s.frame.origin.x
        let ty = m.y - s.frame.origin.y
        current.x += (tx - current.x) * ease
        current.y += (ty - current.y) * ease
        star?.frame.origin = CGPoint(x: current.x - canvas / 2 + 34,
                                     y: current.y - canvas / 2 - 44)
        waveformHost?.frame.origin = CGPoint(x: current.x - waveSize / 2 + 34,
                                             y: current.y - waveSize / 2 - 44)
    }
}

/// Open-concept live waveform: a row of rounded bars whose heights
/// oscillate continuously via TimelineView. No enclosing circle.
private struct WaveformView: View {
    let color: NSColor
    private let bars = 5
    private let barWidth: CGFloat = 2
    private let gap: CGFloat = 1.5
    private let speed: Double = 6

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = Double(i) / Double(bars - 1) * .pi
                    let h = 0.15 + 0.45 * abs(sin(t * speed + phase))
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(Color(color))
                        .frame(width: barWidth, height: max(barWidth, h * 20))
                }
            }
            .frame(width: 44, height: 44, alignment: .center)
        }
        .frame(width: 44, height: 44)
    }
}

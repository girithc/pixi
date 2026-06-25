//
//  OverlayWindow.swift
//  pixi
//
//  Full-screen, borderless, translucent overlay that shows the captured
//  screenshot dimmed plus a teal highlight + 3×3 grid over each target the
//  vision model returned, with the model's reason text. Inspect-only;
//  Esc / click / 6s auto-dismiss.
//
//  Created by Girith Choudhary on 6/24/26.
//

import AppKit
import SwiftUI

@MainActor
final class OverlayWindow {
    static let shared = OverlayWindow()

    private var panel: NSPanel?
    private var monitor: Any?

    private init() {}

    static let teal = NSColor(srgbRed: 0.25, green: 0.88, blue: 0.81, alpha: 1.0)

    func show(image: CGImage, targets: [Target], screenFrame: CGRect) {
        dismiss()

        let p = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false

        let view = OverlayView(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
                               targets: targets,
                               size: screenFrame.size,
                               onDismiss: { [weak self] in self?.dismiss() })
        p.contentView = NSHostingView(rootView: view)
        p.orderFrontRegardless()
        panel = p

        // Esc to dismiss.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }

        // Auto-dismiss after 6s.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self.dismiss()
        }
    }

    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct OverlayView: View {
    let image: NSImage
    let targets: [Target]
    let size: CGSize
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed screenshot.
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .opacity(0.35)

            // Target highlights + grid.
            Canvas { ctx, _ in
                for t in targets {
                    let rect = CGRect(x: t.x * size.width,
                                      y: t.y * size.height,
                                      width: t.w * size.width,
                                      height: t.h * size.height)
                    // Fill.
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 6),
                             with: .color(Color(OverlayWindow.teal).opacity(0.18)))
                    // Stroke.
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 6),
                               with: .color(Color(OverlayWindow.teal)),
                               lineWidth: 2)
                    // 3×3 internal grid over the target.
                    let cols = 3, rows = 3
                    var p = Path()
                    for i in 1..<cols {
                        let x = rect.minX + rect.width * CGFloat(i) / CGFloat(cols)
                        p.move(to: CGPoint(x: x, y: rect.minY))
                        p.addLine(to: CGPoint(x: x, y: rect.maxY))
                    }
                    for j in 1..<rows {
                        let y = rect.minY + rect.height * CGFloat(j) / CGFloat(rows)
                        p.move(to: CGPoint(x: rect.minX, y: y))
                        p.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                    ctx.stroke(p, with: .color(Color(OverlayWindow.teal).opacity(0.5)),
                               lineWidth: 0.5)
                }
            }
            .frame(width: size.width, height: size.height)

            // Reason labels.
            VStack {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, t in
                    if let label = t.label ?? t.reason {
                        Text(label)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}

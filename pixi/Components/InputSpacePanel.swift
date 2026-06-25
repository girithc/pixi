//
//  InputSpacePanel.swift
//  pixi
//
//  A floating, non-activating "keyboard input space" — a Spotlight-like
//  panel that floats above all spaces and accepts a typed command.
//

import SwiftUI
import AppKit

@MainActor
final class InputSpaceController: NSObject {
    static let shared = InputSpaceController()

    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        positionAtBottomCenter(panel)
        // Non-activating, but still take key so the field is typeable.
        NSApp.activate(ignoringOtherApps: false)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        panel.contentView = NSHostingView(rootView: InputSpaceView(
            onSubmit: { [weak self] value in self?.handleSubmit(value) },
            onDismiss: { [weak self] in self?.hide() }
        ))
        self.panel = panel
        return panel
    }

    private func positionAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { panel.center(); return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let x = visible.midX - width / 2
        let y = visible.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func handleSubmit(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { hide(); return }
        hide()
        Task { await WorkflowController.shared.run(prompt: trimmed, source: .typed) }
    }
}

private struct InputSpaceView: View {
    @State private var text: String = ""
    @FocusState private var focused: Bool
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Type a command…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onSubmit { onSubmit(text) }

            Button(action: { onSubmit(text) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            text = ""
            DispatchQueue.main.async { focused = true }
        }
        .onExitCommand { onDismiss() }
    }
}

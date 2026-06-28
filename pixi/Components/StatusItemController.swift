//
//  StatusItemController.swift
//  pixi
//
//  A floating status chip pinned to the top-right of the screen. It reflects
//  the current interaction state and expands on click to show live status —
//  native macOS menu-extra / popover styling, but as an always-on-top panel
//  instead of a menu-bar item.
//
//  Created by Girith Choudhary on 6/26/26.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemController {
    static let shared = StatusItemController()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<StatusChipView>?
    private var cancellables = Set<AnyCancellable>()

    /// Collapsed = icon only; expanded shows the full status body.
    private let collapsedSize = NSSize(width: 32, height: 32)
    private let expandedSize = NSSize(width: 300, height: 240)

    private init() {}

    func start() {
        guard panel == nil else { return }
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = ""
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false
        p.isFloatingPanel = true
        p.level = .floating
        p.identifier = NSUserInterfaceItemIdentifier("pixi.statuschip")
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow
        p.hidesOnDeactivate = false

        let host = NSHostingController(rootView: StatusChipView(
            expanded: false,
            onToggle: { [weak self] in self?.toggleExpanded() }
        ))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        p.contentViewController = host
        hostingController = host

        positionTopRight(p)
        p.orderFrontRegardless()
        panel = p

        // Live-update the chip body when interactions change.
        AITrace.shared.$interactions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    private func positionTopRight(_ p: NSPanel) {
        guard let screen = NSScreen.main else { p.center(); return }
        let visible = screen.visibleFrame
        let f = p.frame
        let x = visible.maxX - f.width - 14
        let y = visible.maxY - f.height - 10
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func toggleExpanded() {
        guard let p = panel else { return }
        let expanded = p.frame.height > collapsedSize.height + 1
        let target = expanded ? collapsedSize : expandedSize
        var f = p.frame
        f.size = target
        // Keep the top-right corner fixed while resizing.
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        f.origin.x = visible.maxX - f.width - 14
        f.origin.y = visible.maxY - f.height - 10
        p.setFrame(f, display: true, animate: true)
        hostingController?.rootView = StatusChipView(
            expanded: !expanded,
            onToggle: { [weak self] in self?.toggleExpanded() }
        )
    }

    private func refresh() {
        // Rebuild the view so it picks up the latest interaction state.
        guard let p = panel else { return }
        let expanded = p.frame.height > collapsedSize.height + 1
        hostingController?.rootView = StatusChipView(
            expanded: expanded,
            onToggle: { [weak self] in self?.toggleExpanded() }
        )
    }
}

/// The floating chip: a compact header (icon + status word) that expands to a
/// live status body. Glass / material styling for a native feel.
private struct StatusChipView: View {
    let expanded: Bool
    let onToggle: () -> Void
    @ObservedObject private var trace = AITrace.shared

    private var active: AITrace.Interaction? {
        trace.interactions.first {
            $0.status == .running || $0.status == .pending
        } ?? trace.interactions.first
    }

    private var running: Bool {
        active?.status == .running || active?.status == .pending
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — icon only when collapsed, click toggles expand.
            Button(action: onToggle) {
                Group {
                    if expanded {
                        HStack(spacing: 7) {
                            Image(systemName: running
                                  ? "bubble.left.and.bubble.right.fill"
                                  : "bubble.left.and.bubble.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tint)
                            Text(headerText)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if running { ProgressView().controlSize(.mini) }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                    } else {
                        Image(systemName: running
                              ? "bubble.left.and.bubble.right.fill"
                              : "bubble.left.and.bubble.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.15)
                bodyContent.padding(12)
            }
        }
        .frame(
            width: expanded ? 300 : 32,
            height: expanded ? 210 : 32,
            alignment: .top
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 10 : 8))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 10 : 8)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var headerText: String {
        guard let it = active else { return "pixi" }
        if running { return it.subtitle.isEmpty ? "Working…" : it.subtitle }
        return it.title
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let it = active {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: it.symbol).foregroundStyle(.tint)
                    Text(it.title).font(.headline)
                    Spacer()
                    statusBadge(it.status)
                }
                Text(it.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Divider().opacity(0.15)

                if let last = it.steps.last {
                    HStack(spacing: 6) {
                        statusBadge(last.status)
                        Text("Step \(last.group) · \(last.label)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text("Waiting…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack {
                    Text("\(it.steps.count) steps")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if it.status == .running || it.status == .pending {
                        controls(it)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No interaction yet")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func statusBadge(_ s: AITrace.Step.Status) -> some View {
        switch s {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            Image(systemName: "circle.dotted").foregroundStyle(.orange)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func controls(_ item: AITrace.Interaction) -> some View {
        HStack(spacing: 4) {
            Button {
                if item.paused {
                    WorkflowController.shared.resume(item.id)
                } else {
                    WorkflowController.shared.pause(item.id)
                }
            } label: {
                Image(systemName: item.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(item.paused ? "Resume" : "Pause")

            Button {
                WorkflowController.shared.stop(item.id)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Stop")
        }
    }
}

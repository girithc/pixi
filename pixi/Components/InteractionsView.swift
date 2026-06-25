//
//  InteractionsView.swift
//  pixi
//
//  Renders the live AI trace. Each interaction is an expandable row:
//  collapse = status + latest subtitle; expand = screenshot with the
//  target overlay rendered inline + the full step chain (capture → ax →
//  [stt] → vision → overlay) with input/output/latency for inspection.
//
//  Created by Girith Choudhary on 6/24/26.
//

import SwiftUI
import AppKit

struct InteractionsView: View {
    @ObservedObject private var trace = AITrace.shared
    @State private var expanded: Set<UUID> = []
    @State private var fullSizeItem: AITrace.Interaction?

    var body: some View {
        List {
            if trace.interactions.isEmpty {
                Text("No interactions yet.")
                    .foregroundStyle(.tertiary)
            }
            ForEach(trace.interactions) { item in
                row(item)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $fullSizeItem) { item in
            if let image = item.screenshot {
                FullSizeScreenshotView(image: image, targets: item.targets ?? [])
            }
        }
    }

    @ViewBuilder
    private func row(_ item: AITrace.Interaction) -> some View {
        let isOpen = expanded.contains(item.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.subtitle).font(.subheadline)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }

                    Spacer(minLength: 8)
                    statusBadge(item.status)
                    Text(item.timeLabel)
                        .font(.subheadline).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if isOpen {
                detail(item)
                    .padding(.top, 8)
                    .padding(.leading, 36)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func detail(_ item: AITrace.Interaction) -> some View {
        let targets = item.targets ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Details").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    copyInteraction(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy interaction to clipboard")
            }

            if let image = item.screenshot {
                VStack(alignment: .leading, spacing: 6) {
                    screenshotPreview(image, targets: targets)
                    HStack {
                        Text("Targets: \(targets.count)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Full size") { fullSizeItem = item }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if !targets.isEmpty {
                    Text(targetsJSON(targets))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05)))
                }
            }

            Text("Steps").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.steps) { step in
                    stepRow(step)
                }
            }
        }
    }

    private func copyInteraction(_ item: AITrace.Interaction) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(interactionText(item), forType: .string)
    }

    private func interactionText(_ item: AITrace.Interaction) -> String {
        var lines: [String] = []
        lines.append("\(item.title)")
        lines.append("Subtitle: \(item.subtitle)")
        lines.append("Status: \(statusName(item.status))")
        lines.append("")
        lines.append("Steps:")
        for (i, step) in item.steps.enumerated() {
            let ms = step.durationMs > 0 ? " (\(step.durationMs)ms)" : ""
            lines.append("\(i + 1). [\(statusName(step.status))] \(step.label)\(ms)")
            if !step.input.isEmpty { lines.append("   in:  \(step.input)") }
            if !step.output.isEmpty { lines.append("   out: \(step.output)") }
        }
        if let targets = item.targets, !targets.isEmpty {
            lines.append("")
            lines.append("Targets:")
            lines.append(targetsJSON(targets))
        }
        return lines.joined(separator: "\n")
    }

    private func statusName(_ s: AITrace.Step.Status) -> String {
        switch s {
        case .pending: "pending"; case .running: "running"
        case .success: "success"; case .failed: "failed"
        }
    }

    private func targetsJSON(_ targets: [Target]) -> String {
        let data = (try? JSONEncoder().encode(targets)) ?? Data()
        let obj = try? JSONSerialization.jsonObject(with: data)
        let pretty = try? JSONSerialization.data(withJSONObject: obj ?? [],
                                                  options: [.prettyPrinted, .sortedKeys])
        return String(data: pretty ?? Data(), encoding: .utf8) ?? "[]"
    }

    /// Screenshot + inline target overlay, scaled to fit.
    @ViewBuilder
    private func screenshotPreview(_ image: NSImage, targets: [Target]) -> some View {
        let aspect = image.size.height / max(image.size.width, 1)
        let width: CGFloat = 340
        let height = width * aspect
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
                .opacity(0.9)

            Canvas { ctx, size in
                for t in targets {
                    let rect = CGRect(x: t.x * size.width,
                                      y: t.y * size.height,
                                      width: t.w * size.width,
                                      height: t.h * size.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                             with: .color(Color(OverlayWindow.teal).opacity(0.18)))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 4),
                               with: .color(Color(OverlayWindow.teal)),
                               lineWidth: 1.5)
                }
            }
            .frame(width: width, height: height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func stepRow(_ step: AITrace.Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statusBadge(step.status)
                Text(step.label).font(.subheadline.weight(.semibold))
                Spacer()
                if step.durationMs > 0 {
                    Text("\(step.durationMs)ms")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            if !step.input.isEmpty {
                Text("Input")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(step.input)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            if !step.output.isEmpty {
                Text("Output")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(step.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusBadge(_ status: AITrace.Step.Status) -> some View {
        switch status {
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
}

/// Full-size inspect view: the screenshot at natural resolution in a
/// scrollable area with the target overlay drawn at the same scale.
private struct FullSizeScreenshotView: View {
    let image: NSImage
    let targets: [Target]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Screenshot — \(Int(image.size.width))×\(Int(image.size.height))  ·  \(targets.count) target(s)")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: image.size.width, height: image.size.height)

                    Canvas { ctx, size in
                        for t in targets {
                            let rect = CGRect(x: t.x * size.width,
                                              y: t.y * size.height,
                                              width: t.w * size.width,
                                              height: t.h * size.height)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 6),
                                     with: .color(Color(OverlayWindow.teal).opacity(0.18)))
                            ctx.stroke(Path(roundedRect: rect, cornerRadius: 6),
                                       with: .color(Color(OverlayWindow.teal)),
                                       lineWidth: 2)
                        }
                    }
                    .frame(width: image.size.width, height: image.size.height)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 420)
    }
}

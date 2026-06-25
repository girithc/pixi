//
//  ListAppsTool.swift
//  pixi
//
//  List installed macOS applications, tiered: running apps first, then all
//  installed apps. Filesystem scan of standard app dirs — fast, no
//  permission. On-demand (not injected every turn).
//
//  Created by Girith Choudhary on 6/25/26.
//

import AppKit
import Foundation

@MainActor
struct ListAppsTool: Tool {
    let name = "list_apps"
    let summary = "Installed apps, running ones first."
    let description = "Returns installed macOS apps tiered: first the currently-running apps, then all installed apps. Call before open_app to confirm an app is installed and get its exact name, and to see which apps are already open. Avoids wasting steps on apps that aren't installed."
    let argsSchema = "{}"

    private let dirs = ["/Applications", "/System/Applications",
                        "/System/Applications/Utilities", "~/Applications"]

    func run(args: [String: Any], interactionId: UUID) async -> ToolResult {
        let fm = FileManager.default
        var installed: [String] = []
        for d in dirs {
            let path = (d as NSString).expandingTildeInPath
            guard let names = try? fm.contentsOfDirectory(atPath: path) else { continue }
            installed += names.filter { $0.hasSuffix(".app") }
                .map { $0.replacingOccurrences(of: ".app", with: "") }
        }
        let all = Array(Set(installed)).sorted()
        let running = Array(Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.localizedName }
        )).sorted()
        let notRunning = all.filter { !running.contains($0) }

        var out = "RUNNING:\n" + running.joined(separator: ", ")
        out += "\n\nINSTALLED (not running):\n" + notRunning.joined(separator: ", ")
        return ToolResult(ok: true, output: out, error: nil)
    }
}

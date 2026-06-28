//
//  ContentView.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selection: SidebarItem? = .interactions

    var body: some View {
        // Plain HStack split — NavigationSplitView forces a system material
        // on the sidebar column that can't be cleared. Bare glass needs none.
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
                .frame(width: 220)
                .background(.clear)

            Divider()
                .opacity(0.15)

            MainContent(item: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .background(WindowAccessor { window in
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            // Kill the default white window background so liquid glass
            // cards overlay a bare, transparent surface.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.hasShadow = true
        })
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}

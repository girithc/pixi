//
//  pixiApp.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI
import AppKit
import Carbon

@main
struct pixiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 600)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var napActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        napActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "CursorBuddy cursor tracking"
        )
        CursorBuddy.shared.start()

        // Option + K — toggle the typed-command input panel.
        HotkeyManager.shared.register(
            keyCode: kVK_ANSI_K,
            modifiers: UInt32(optionKey),
            id: 1
        ) {
            InputSpaceController.shared.toggle()
        }

        // Option + Space — toggle voice-listen mode on the cursor buddy.
        HotkeyManager.shared.register(
            keyCode: kVK_Space,
            modifiers: UInt32(optionKey),
            id: 2
        ) {
            CursorBuddy.shared.toggleListening()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }
}

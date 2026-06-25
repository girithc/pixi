//
//  ScreenCapture.swift
//  pixi
//
//  Grabs the current main screen as a CGImage + the screen frame (for
//  overlay scaling) using ScreenCaptureKit. Requires Screen Recording TCC,
//  already requested via Permissions.requestScreenCapture.
//
//  Created by Girith Choudhary on 6/24/26.
//

import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
enum ScreenCapture {
    /// Captures the main display. Returns (image, screenFrame in global coords).
    static func captureMainScreen() async -> (image: CGImage, frame: CGRect)? {
        guard let screen = NSScreen.main else { return nil }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false),
              let display = content.displays.first else { return nil }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width)
        config.height = Int(screen.frame.height)
        config.scalesToFit = false
        config.capturesShadowsOnly = false

        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config) else { return nil }

        return (image, screen.frame)
    }
}

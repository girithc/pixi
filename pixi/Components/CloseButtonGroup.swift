//
//  CloseButtonGroup.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI

struct CloseButtonGroup: View {
    @Environment(\.dismiss) private var dismiss

    private let dotSize: CGFloat = 12
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            dot(.red, action: { NSApp.terminate(nil) })
            dot(.orange, action: minimize)
            dot(.green, action: { NSApp.keyWindow?.toggleFullScreen(nil) })
        }
        .padding(8)
        .buttonStyle(.plain)
    }

    private func dot(_ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
        }
    }

    private func minimize() {
        NSApp.keyWindow?.miniaturize(nil)
    }
}

//
//  SidebarItem.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, interactions, search, library, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .interactions: "Interactions"
        case .search: "Automations"
        case .library: "Screen Capture"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .interactions: "bubble.left.and.bubble.right.fill"
        case .search: "gearshape.2.fill"
        case .library: "rectangle.dashed.and.paperclip"
        case .settings: "gearshape.fill"
        }
    }
}

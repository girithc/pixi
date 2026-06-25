//
//  MainContent.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI

struct MainContent: View {
    let item: SidebarItem?

    var body: some View {
        Group {
            if item == .settings {
                SettingsView()
            } else if item == .interactions {
                InteractionsView()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: item?.systemImage ?? "house.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.tint)
                    Text(item?.label ?? "Home")
                        .font(.title.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(.clear)
        .ignoresSafeArea(edges: [.top, .bottom])
    }
}

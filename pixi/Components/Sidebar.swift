//
//  Sidebar.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 8) {
            CloseButtonGroup()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.leading, 6)

            VStack(spacing: 10) {
                ForEach(SidebarItem.allCases) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
        .padding(.leading, 8)
        .padding(.bottom, 8)
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        Button {
            selection = item
        } label: {
            Label(item.label, systemImage: item.systemImage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.white.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }
}

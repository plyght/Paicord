//
//  LargeBaseplate.swift
//  Paicord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import DiscordModels
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect
import SwiftUIX

// if on macos or ipad
struct LargeBaseplate: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @AppStorage("Paicord.ShowingMembersSidebar") var showingInspector = true

  @State var currentGuildStore: GuildStore? = nil
  @State var currentChannelStore: ChannelStore? = nil

  @State private var columnVisibility: NavigationSplitViewVisibility =
    .doubleColumn

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(currentGuildStore: $currentGuildStore)
        .environment(\.guildStore, currentGuildStore)
        .environment(\.channelStore, currentChannelStore)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          ProfileBar()
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle(currentGuildStore?.guild?.name ?? "Direct Messages")
        .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 360)

    } detail: {
      Group {
        if let currentChannelStore {
          ZStack(alignment: .trailing) {
            ChatView(vm: currentChannelStore)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .padding(.trailing, showingInspector ? 250 : 0)
              .animation(nil, value: showingInspector)
              .id(currentChannelStore.channelId)  // force view update

            HStack(spacing: 0) {
              Divider()
              MemberSidebarView(
                guildStore: currentGuildStore,
                channelStore: currentChannelStore
              )
              .frame(width: 250)
            }
            .frame(width: 251)
            .offset(x: showingInspector ? 0 : 251)
            .animation(
              .spring(response: 0.32, dampingFraction: 0.86),
              value: showingInspector
            )
          }
          .environment(\.guildStore, currentGuildStore)
          .environment(\.channelStore, currentChannelStore)
        } else {
          // placeholder
          VStack {
            Text(":3")
              .font(.largeTitle)
              .foregroundStyle(.secondary)

            Text("Select a channel to start chatting")
              .foregroundStyle(.secondary)
              .font(.title2)
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigation) {
          Button {
            columnVisibility =
              (columnVisibility != .detailOnly) ? .detailOnly : .doubleColumn
          } label: {
            Label("Toggle Sidebar", systemImage: "sidebar.left")
          }
        }
      }
    }
    .toolbar {
      Button {
        showingInspector.toggle()
      } label: {
        Label("Toggle Member List", systemImage: "sidebar.right")
      }
    }
    .task(id: appState.selectedGuild) {
      if let selected = appState.selectedGuild {
        self.currentGuildStore = gw.getGuildStore(for: selected)
      } else {
        self.currentGuildStore = nil
      }
    }
    .task(id: appState.selectedChannel) {
      if let selected = appState.selectedChannel {
        // there is a likelihood that currentGuildStore is wrong when this runs
        // but i dont think it will be a problem maybe.
        self.currentChannelStore = gw.getChannelStore(
          for: selected,
          from: self.currentGuildStore
        )
      } else {
        self.currentChannelStore = nil
      }
    }
  }
}

#Preview {
  LargeBaseplate()
}

//
//  GuildScrollBar.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 23/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUIX

struct GuildScrollBar: View {
  @Environment(\.gateway) var gw

  private var listedGuildIDs: Set<String> {
    var ids = Set<String>()
    for folder in gw.settings.userSettings.guildFolders.folders {
      for guildID in folder.guildIds {
        ids.insert(guildID.description)
      }
    }
    return ids
  }

  private var unlistedGuilds: [Guild] {
    guard let userID = gw.user.currentUser?.id else { return [] }
    let listed = listedGuildIDs
    return gw.user.guilds.values
      .filter { !listed.contains($0.id.rawValue) }
      .sorted { a, b in
        let aJoined = gw.user.guilds[a.id]?.members?.first(where: { $0.user?.id == userID })?.joined_at
        let bJoined = gw.user.guilds[b.id]?.members?.first(where: { $0.user?.id == userID })?.joined_at
        return (bJoined ?? .init(date: .now)) < (aJoined ?? .init(date: .now))
      }
  }

  var body: some View {
    ScrollFadeMask {
      LazyVStack {
        GuildButton(guild: nil)

        Divider()
          .padding(.horizontal, 8)

        ForEach(unlistedGuilds, id: \.id) { guild in
          GuildButton(guild: guild)
        }
        ForEach(
          0..<gw.settings.userSettings.guildFolders.folders.count,
          id: \.self
        ) { folderIndex in
          let folder = gw.settings.userSettings.guildFolders.folders[
            folderIndex
          ]
          Group {
            if folder.hasID == false {
              if let guildIDString = folder.guildIds.first?.description,
                let guild = gw.user.guilds[GuildSnowflake(guildIDString)]
              {
                GuildButton(guild: guild)
              }
            } else {
              let guilds = folder.guildIds.compactMap { guildID in
                let guildID = GuildSnowflake(guildID.description)
                return gw.user.guilds[guildID]
              }
              GuildButton(folder: folder, guilds: guilds)
            }
          }
        }
      }
      .safeAreaPadding(.all, 10)
    }
  }
}

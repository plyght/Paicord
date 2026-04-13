//
//  GuildView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 22/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SDWebImageSwiftUI
import SwiftUIX

struct GuildView: View {
  var guild: GuildStore
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme
  private var uncategorizedChannels: [DiscordChannel] {
    guild.channels.values
      .filter { $0.parent_id == nil }
      .sorted { lhs, rhs in
        let lhsIsCategory = lhs.type == .guildCategory
        let rhsIsCategory = rhs.type == .guildCategory
        if lhsIsCategory == rhsIsCategory {
          return (lhs.position ?? 0) < (rhs.position ?? 0)
        } else {
          return !lhsIsCategory && rhsIsCategory
        }
      }
  }

  var body: some View {
    ScrollFadeMask {
      LazyVStack(spacing: 0) {
        Utils.GuildBannerURL(guild: guild, animated: true) { bannerURL in
          if let bannerURL {
            AnimatedImage(url: bannerURL)
              .resizable()
              .aspectRatio(16 / 9, contentMode: .fill)
          }
        }

        if idiom == .phone {
          VStack(spacing: 0) {
            VStack(alignment: .leading) {
              Text(guild.guild?.name ?? "Unknown Guild")
                .font(.title3)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
              Text("\(guild.guild?.member_count ?? 0) members")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()
          }
        }

        LazyVStack(spacing: 1) {
          ForEach(uncategorizedChannels) { channel in
            ChannelButton(channels: guild.channels, channel: channel)
              .padding(.horizontal, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .frame(maxWidth: .infinity)
    #if os(macOS)
    .background(.clear)
    #else
    .background(theme.common.secondaryBackground.opacity(0.5))
    #endif
  }
}

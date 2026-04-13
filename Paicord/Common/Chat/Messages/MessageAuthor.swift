//
//  Username.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 11/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SDWebImageSwiftUI
import SwiftUIX

extension MessageCell {
  enum MessageAuthor {
    struct Avatar: View {
      var message: DiscordChannel.Message
      var guildStore: GuildStore?
      @Binding var profileOpen: Bool
      var body: some View {
        Button {
          guard message.author != nil else { return }
          ImpactGenerator.impact(style: .light)
          profileOpen = true
        } label: {
          let guildstoremember =
            message.author != nil
            ? guildStore?.members[message.author!.id] : nil
          Profile.Avatar(
            member: guildstoremember ?? message.member,
            user: message.author?.toPartialUser()
          )
          .profileShowsAvatarDecoration()
          .frame(width: avatarSize, height: avatarSize)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $profileOpen) {
          if let userId = message.author?.id, let user = message.author {
            ProfilePopoutView(
              guild: guildStore,
              member: guildStore?.members[userId] ?? message.member,
              user: user.toPartialUser()
            )
          }
        }
        .frame(maxHeight: .infinity, alignment: .top)  // align pfp to top of cell
      }
    }

    struct Username: View {
      var message: DiscordChannel.Message
      var guildStore: GuildStore?
      @Binding var profileOpen: Bool

      var body: some View {
        Button {
          guard message.author != nil else { return }
          ImpactGenerator.impact(style: .light)
          profileOpen = true
        } label: {
          if let guildStore, let userID = message.author?.id {
            let member = guildStore.members[userID] ?? message.member
            let color = guildStore.roleColor(for: member)

            Text(
              member?.nick ?? message.author?.global_name ?? message.author?
                .username
                ?? "Unknown"
            )
            .foregroundStyle(color != nil ? color! : .primary)
          } else {
            Text(
              message.author?.global_name ?? message.author?.username
                ?? "Unknown"
            )
          }
        }
        .buttonStyle(.plain)
        #if os(iOS)
          .font(.callout)
        #elseif os(macOS)
          .font(.body)
        #endif
        .fontWeight(.semibold)
      }
    }
  }
}

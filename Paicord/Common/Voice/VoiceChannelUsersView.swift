//
//  VoiceChannelUsersView.swift
//  Paicord
//
//  Shows the list of users currently in a voice channel,
//  displayed under the voice channel in the sidebar.
//

import PaicordLib
import SwiftUI

struct VoiceChannelUsersView: View {
  @Environment(\.gateway) var gw
  let channelId: ChannelSnowflake
  let guildStore: GuildStore?

  private var voiceUsers: [VoiceState] {
    guard let guildStore else { return [] }
    return guildStore.voiceStates.values
      .filter { $0.channel_id == channelId }
      .sorted { $0.user_id.rawValue < $1.user_id.rawValue }
  }

  var body: some View {
    if !voiceUsers.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(voiceUsers, id: \.user_id) { state in
          voiceUserRow(state: state)
        }
      }
      .padding(.leading, 28)
      .padding(.vertical, 2)
    }
  }

  @ViewBuilder
  private func voiceUserRow(state: VoiceState) -> some View {
    let user = gw.user.users[state.user_id]
    let member = guildStore?.members[state.user_id]
    let displayName = member?.nick ?? user?.global_name ?? user?.username ?? "Unknown"

    HStack(spacing: 6) {
      if let user {
        Profile.Avatar(member: member, user: user)
          .frame(width: 20, height: 20)
      } else {
        Circle()
          .fill(Color.gray.opacity(0.3))
          .frame(width: 20, height: 20)
      }

      Text(displayName)
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(
          memberColor(member: member) ?? .primary
        )

      Spacer(minLength: 0)

      HStack(spacing: 2) {
        if state.self_mute || state.mute {
          Image(systemName: "mic.slash.fill")
            .font(.system(size: 9))
            .foregroundStyle(.red.opacity(0.7))
        }
        if state.self_deaf || state.deaf {
          Image(systemName: "speaker.slash.fill")
            .font(.system(size: 9))
            .foregroundStyle(.red.opacity(0.7))
        }
        if state.self_video {
          Image(systemName: "video.fill")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        if state.self_stream == true {
          Image(systemName: "display")
            .font(.system(size: 9))
            .foregroundStyle(.purple)
        }
      }
    }
    .padding(.vertical, 1)
  }

  private func memberColor(member: Guild.PartialMember?) -> Color? {
    guard let member, let roles = member.roles, let guildStore else { return nil }
    for role in guildStore.roles.values {
      if roles.contains(role.id), let color = role.color.asColor() {
        return color
      }
    }
    return nil
  }
}

//
//  VoiceChannelRow.swift
//  Paicord
//
//  A voice channel row in the sidebar that supports joining
//  and shows connected users underneath.
//

import PaicordLib
import SwiftUI

struct VoiceChannelRow: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.guildStore) var guildStore
  @State private var isHovered = false

  let channel: DiscordChannel
  let channels: [ChannelSnowflake: DiscordChannel]

  private var isConnectedHere: Bool {
    gw.voice.connectedChannelId == channel.id
  }

  private var voiceUserCount: Int {
    guard let guildStore else { return 0 }
    return guildStore.voiceStates.values
      .filter { $0.channel_id == channel.id }
      .count
  }

  private var shouldHide: Bool {
    guard let guildStore else { return false }
    return guildStore.hasPermission(
      channel: channel,
      .viewChannel
    ) == false
  }

  var body: some View {
    if !shouldHide {
      VStack(alignment: .leading, spacing: 0) {
        Button {
          joinVoice()
        } label: {
          HStack {
            Image(systemName: "speaker.wave.2.fill")
              .imageScale(.medium)
              .foregroundStyle(isConnectedHere ? .green : .primary)

            Text(channel.name ?? "unknown")
              .foregroundStyle(isConnectedHere ? .green : .primary)

            Spacer(minLength: 4)

            if voiceUserCount > 0 {
              Text("\(voiceUserCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                  Capsule().fill(Color.gray.opacity(0.2))
                )
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: 35)
          .padding(.horizontal, 12)
          .lineLimit(1)
          .background(
            Group {
              if isHovered {
                Color.gray.opacity(0.2)
              } else if isConnectedHere {
                Color.green.opacity(0.08)
              } else {
                Color.clear
              }
            }
            .clipShape(.rounded)
          )
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .tint(.primary)

        VoiceChannelUsersView(
          channelId: channel.id,
          guildStore: guildStore
        )
      }
    }
  }

  private func joinVoice() {
    if isConnectedHere {
      Task { await gw.voice.disconnect() }
    } else {
      Task {
        await gw.voice.joinChannel(
          channelId: channel.id,
          guildId: guildStore?.guildId,
          channelName: channel.name,
          guildName: guildStore?.guild?.name
        )
      }
    }
  }
}

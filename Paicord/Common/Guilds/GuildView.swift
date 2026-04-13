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
              .frame(maxWidth: .infinity)
              .clipShape(.rect(cornerRadius: 12, style: .continuous))
              .padding(.horizontal, 8)
              .padding(.top, 8)
              .padding(.bottom, 4)
          }
        }

        GuildHeader(guild: guild)

        LazyVStack(spacing: Spacing.tiny) {
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

private struct GuildHeader: View {
  let guild: GuildStore
  @Environment(\.gateway) var gw
  @Environment(\.theme) var theme
  @State private var isHovering = false
  @State private var showLeaveConfirm = false
  @State private var isMenuOpen = false

  private var isOwner: Bool {
    guard
      let userID = gw.user.currentUser?.id,
      let ownerID = guild.guild?.owner_id
    else { return false }
    return userID == ownerID
  }

  private var memberCountText: String {
    let count = guild.guild?.member_count ?? 0
    return "\(count) \(count == 1 ? "member" : "members")"
  }

  var body: some View {
    VStack(spacing: 0) {
      Menu {
        if let name = guild.guild?.name {
          Button {
            copyToClipboard(name)
          } label: {
            Label("Copy Server Name", systemImage: "doc.on.doc")
          }
        }
        if let id = guild.guild?.id {
          Button {
            copyToClipboard(id.rawValue)
          } label: {
            Label("Copy Server ID", systemImage: "number")
          }
        }
        if !isOwner, guild.guild != nil {
          Divider()
          Button(role: .destructive) {
            showLeaveConfirm = true
          } label: {
            Label(
              "Leave Server",
              systemImage: "rectangle.portrait.and.arrow.right"
            )
          }
        }
      } label: {
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(guild.guild?.name ?? "Unknown Guild")
              .font(.title3)
              .bold()
              .foregroundStyle(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(memberCountText)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.down")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Sidebar.headerHeight)
        .contentShape(.rect)
      }
      #if os(macOS)
        .menuStyle(.button)
        .menuIndicator(.hidden)
      #endif
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Rectangle()
          .fill(theme.common.secondaryBackground.opacity(isHovering ? 0.35 : 0.0))
      )
      .onHover { hovering in
        withAnimation(.easeOut(duration: 0.12)) {
          isHovering = hovering
        }
      }

      Divider()
    }
    .confirmationDialog(
      "Leave \(guild.guild?.name ?? "Server")?",
      isPresented: $showLeaveConfirm,
      titleVisibility: .visible
    ) {
      Button("Leave Server", role: .destructive) {
        Task { await leaveGuild() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You won't be able to rejoin unless you are re-invited.")
    }
  }

  private func copyToClipboard(_ value: String) {
    #if os(macOS)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(value, forType: .string)
    #elseif os(iOS)
      UIPasteboard.general.string = value
    #endif
    ImpactGenerator.impact(style: .light)
  }

  private func leaveGuild() async {
    guard let id = guild.guild?.id else { return }
    _ = try? await gw.client.leaveGuild(id: id)
  }
}

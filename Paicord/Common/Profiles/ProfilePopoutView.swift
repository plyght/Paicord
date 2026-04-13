//
//  ProfilePopoutView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 18/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import ColorCube
import PaicordLib
import SDWebImageSwiftUI
import SwiftPrettyPrint
import SwiftUIX

/// Sheet on iOS, else its the popover on macOS/ipadOS.
struct ProfilePopoutView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.channelStore) var channel
  var guild: GuildStore?
  let member: Guild.PartialMember?
  let user: PartialUser

  @Environment(\.colorScheme) var systemColorScheme
  @State private var profile: DiscordUser.Profile?
  @State private var showMainProfile: Bool = false

  public init(
    guild: GuildStore? = nil,
    member: Guild.PartialMember? = nil,
    user: PartialUser,
    profile: DiscordUser.Profile? = nil
  ) {
    self.guild = guild
    self.member = member
    self.user = user
    self._profile = State(initialValue: profile)
  }

  var colorScheme: ColorScheme? {
    // if there is a first theme color, get it
    guard
      let firstColor =
        showMainProfile
        ? profile?.user_profile?.theme_colors?.first
        : profile?.guild_member_profile?.theme_colors?.first
          ?? profile?.user_profile?.theme_colors?.first
    else {
      return nil
    }
    return firstColor.asColor()?.suggestedColorScheme()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading) {
        bannerView

        profileBody
          .padding()
      }
      .minWidth(idiom == .phone ? nil : 300)  // popover limits on larger devices
      .maxWidth(idiom == .phone ? nil : 300)  // popover limits on larger devices
      .task(fetchProfile)
      .task(grabColor)  // way faster than profile fetch
      .scenePadding(.bottom)
    }
    .minHeight(idiom == .phone ? nil : 400)  // popover limits on larger devices
    .presentationDetents([.medium, .large])
    .scrollClipDisabled()
    .background(
      Profile.ThemeColorsBackground(
        colors: showMainProfile
          ? profile?.user_profile?.theme_colors
          : profile?.guild_member_profile?.theme_colors
            ?? profile?.user_profile?.theme_colors
      )
      .overlay(.ultraThinMaterial)
    )
    .ignoresSafeArea(.container, edges: .bottom)
    .environment(\.colorScheme, colorScheme ?? systemColorScheme)
    #if os(iOS)
      .presentationBackground(.ultraThinMaterial)
    #endif
  }

  @ViewBuilder
  var bannerView: some View {
    Utils.UserBannerURL(
      user: user,
      profile: profile,
      mainProfileBanner: showMainProfile,
      animated: true
    ) { bannerURL in
      WebImage(url: bannerURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(3, contentMode: .fill)
        default:
          let color =
            showMainProfile
            ? profile?.user_profile?.theme_colors?.first
              ?? profile?.user_profile?.accent_color
            : profile?.guild_member_profile?.theme_colors?.first ?? profile?
              .user_profile?.theme_colors?.first ?? profile?
              .guild_member_profile?.accent_color
              ?? profile?.user_profile?.accent_color
          Rectangle()
            .aspectRatio(3, contentMode: .fit)
            .foregroundStyle(color?.asColor() ?? accentColor)
        }
      }
      .reverseMask(alignment: .bottomLeading) {
        Circle()
          .frame(width: 80, height: 80)
          .padding(.leading, 16)
          .scaleEffect(1.15)
          .offset(x: -1, y: 40)
      }
      .overlay(alignment: .bottomLeading) {
        Profile.AvatarWithPresence(
          member: member,
          user: user
        )
        .profileAnimated()
        .profileShowsAvatarDecoration()
        .frame(width: 80, height: 80)
        .padding(.leading, 16)
        .offset(y: 40)
      }
      .padding(.bottom, 30)
    }
  }

  @ViewBuilder
  var profileBody: some View {
    LazyVStack(alignment: .leading, spacing: 4) {
      let profileMeta: DiscordUser.Profile.Metadata? = {
        if showMainProfile {
          return profile?.user_profile
        } else {
          return profile?.guild_member_profile ?? profile?.user_profile
        }
      }()
      Text(
        member?.nick ?? user.global_name ?? user.username ?? "Unknown User"
      )
      .font(.title2)
      .bold()
      .lineLimit(1)
      .minimumScaleFactor(0.5)

      FlowLayout(xSpacing: 8, ySpacing: 2) {
        Group {
          Text(verbatim: "@\(user.username ?? "unknown")")
          if let pronouns = profileMeta?.pronouns
            ?? (showMainProfile
              ? user.pronouns : member?.pronouns ?? user.pronouns),
            !pronouns.isEmpty
          {
            Text(verbatim: "•")
            Text(pronouns)
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)

        Profile.BadgesView(
          profile: profile,
          member: member,
          user: user
        )
      }

      if let bio =
        (profileMeta?.bio ?? profile?.user_profile?.bio)?.isEmpty ?? true
        ? profile?.user_profile?.bio
        : profileMeta?.bio ?? profile?.user_profile?.bio
      {
        MarkdownText(content: bio, channelStore: channel)
          .equatable()
      }

      if let conns = profile?.connected_accounts, !conns.isEmpty {
        connectionsSection(conns)
      }

      if let mutuals = profile?.mutual_guilds, !mutuals.isEmpty {
        mutualGuildsSection(mutuals)
      }

      if let friends = profile?.mutual_friends, !friends.isEmpty {
        mutualFriendsSection(
          friends,
          totalCount: profile?.mutual_friends_count
        )
      }
    }
  }

  @ViewBuilder
  func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .padding(.top, 10)
  }

  @ViewBuilder
  func connectionsSection(_ conns: [DiscordUser.PartialConnection]) -> some View
  {
    sectionHeader("Connections")
    FlowLayout(xSpacing: 6, ySpacing: 6) {
      ForEach(conns, id: \.id) { conn in
        HStack(spacing: 6) {
          Image(systemName: Self.connectionSymbol(for: conn.type))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(conn.name ?? Self.connectionDisplayName(conn.type))
            .font(.caption)
            .lineLimit(1)
          if conn.verified {
            Image(systemName: "checkmark.seal.fill")
              .font(.caption2)
              .foregroundStyle(.blue)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
          Capsule()
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
      }
    }
  }

  @ViewBuilder
  func mutualGuildsSection(_ mutuals: [DiscordUser.Profile.MutualGuild])
    -> some View
  {
    sectionHeader(
      "\(mutuals.count) Mutual Server\(mutuals.count == 1 ? "" : "s")"
    )
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 10) {
        ForEach(mutuals, id: \.id) { mg in
          mutualGuildItem(mg)
        }
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 1)
    }
  }

  @ViewBuilder
  func mutualGuildItem(_ mg: DiscordUser.Profile.MutualGuild) -> some View {
    let guild = gw.user.guilds[mg.id]
    VStack(spacing: 4) {
      Group {
        if let icon = guild?.icon {
          let url =
            CDNEndpoint.guildIcon(guildId: mg.id, icon: icon).url + "?size=80"
          WebImage(url: URL(string: url))
            .resizable()
            .scaledToFill()
        } else {
          let initials =
            (guild?.name ?? "?")
            .split(separator: " ")
            .compactMap(\.first)
            .reduce("") { $0 + String($1) }
          Rectangle()
            .fill(.gray.opacity(0.3))
            .overlay(
              Text(initials)
                .font(.caption)
                .bold()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(2)
            )
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

      Text(mg.nick ?? guild?.name ?? "Unknown")
        .font(.caption2)
        .lineLimit(1)
        .frame(maxWidth: 60)
    }
  }

  @ViewBuilder
  func mutualFriendsSection(_ friends: [PartialUser], totalCount: Int?)
    -> some View
  {
    let count = totalCount ?? friends.count
    sectionHeader("\(count) Mutual Friend\(count == 1 ? "" : "s")")
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 10) {
        ForEach(friends, id: \.id) { friend in
          mutualFriendItem(friend)
        }
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 1)
    }
  }

  @ViewBuilder
  func mutualFriendItem(_ friend: PartialUser) -> some View {
    VStack(spacing: 4) {
      Group {
        if let url = Utils.fetchUserAvatarURL(
          member: nil,
          guildId: nil,
          user: friend,
          animated: false
        ) {
          WebImage(url: url)
            .resizable()
            .scaledToFill()
        } else {
          Circle().fill(.gray.opacity(0.3))
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(Circle())

      Text(friend.global_name ?? friend.username ?? "Unknown")
        .font(.caption2)
        .lineLimit(1)
        .frame(maxWidth: 60)
    }
  }

  static func connectionSymbol(for service: DiscordUser.Connection.Service)
    -> String
  {
    switch service.rawValue {
    case "spotify", "amazon-music": return "music.note"
    case "steam", "xbox", "playstation", "battlenet", "epicgames",
      "riotgames", "leagueoflegends", "roblox", "bungie":
      return "gamecontroller.fill"
    case "github": return "chevron.left.forwardslash.chevron.right"
    case "youtube", "twitch": return "play.rectangle.fill"
    case "twitter", "bluesky", "mastodon": return "bubble.left.fill"
    case "instagram", "facebook", "tiktok": return "camera.fill"
    case "reddit": return "newspaper.fill"
    case "paypal", "ebay": return "creditcard.fill"
    case "crunchyroll": return "tv.fill"
    case "domain": return "globe"
    default: return "link"
    }
  }

  static func connectionDisplayName(_ service: DiscordUser.Connection.Service)
    -> String
  {
    switch service.rawValue {
    case "amazon-music": return "Amazon Music"
    case "battlenet": return "Battle.net"
    case "bungie": return "Bungie"
    case "bluesky": return "Bluesky"
    case "crunchyroll": return "Crunchyroll"
    case "domain": return "Domain"
    case "ebay": return "eBay"
    case "epicgames": return "Epic Games"
    case "facebook": return "Facebook"
    case "github": return "GitHub"
    case "instagram": return "Instagram"
    case "leagueoflegends": return "League of Legends"
    case "mastodon": return "Mastodon"
    case "paypal": return "PayPal"
    case "playstation": return "PlayStation"
    case "reddit": return "Reddit"
    case "riotgames": return "Riot Games"
    case "roblox": return "Roblox"
    case "spotify": return "Spotify"
    case "skype": return "Skype"
    case "steam": return "Steam"
    case "tiktok": return "TikTok"
    case "twitch": return "Twitch"
    case "twitter": return "X"
    case "xbox": return "Xbox"
    case "youtube": return "YouTube"
    default: return service.rawValue.capitalized
    }
  }

  @Sendable
  func fetchProfile() async {
    guard profile == nil else { return }
    let res = try? await gw.client.getUserProfile(
      userID: user.id,
      withMutualGuilds: true,
      withMutualFriends: true,
      withMutualFriendsCount: true,
      guildID: guild?.guildId
    )
    do {
      // ensure request was successful
      try res?.guardSuccess()
      let profile = try res?.decode()
      self.profile = profile
    } catch {
      if let error = res?.asError() {
        appState.error = error
      } else {
        appState.error = error
      }
    }
  }

  @State var accentColor = Color.clear

  @Sendable
  func grabColor() async {
    let cc = CCColorCube()
    // use sdwebimage's image manager, get the avatar image and extract colors using colorcube
    let m: Guild.PartialMember? = showMainProfile ? nil : member
    guard
      let avatarURL = Utils.fetchUserAvatarURL(
        member: m,
        guildId: guild?.guildId,
        user: user,
        animated: false
      )
    else {
      return
    }
    let imageManager: SDWebImageManager = .shared
    imageManager.loadImage(
      with: avatarURL,
      progress: nil
    ) { image, _, error, _, _, _ in
      guard let image else {
        return
      }
      let colors = cc.extractColors(
        from: image,
        flags: [.orderByBrightness, .avoidBlack, .avoidWhite]
      )
      if let firstColor = colors?.first {
        DispatchQueue.main.async {
          self.accentColor = Color(firstColor)
        }
      } else {
      }
    }
  }
}

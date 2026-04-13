//
//  ProfileBar.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 24/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SDWebImageSwiftUI
import SwiftPrettyPrint
import SwiftUIX

struct ProfileBar: View {
  @Environment(\.gateway) var gw
  #if os(macOS)
    @Environment(\.openWindow) var openWindow
  #endif

  @State var showingUsername = false
  @State var showingPopover = false
  @State var barHovered = false

  private var currentCustomStatus: Gateway.Activity? {
    guard
      let session = gw.user.sessions.first(where: { $0.id == "all" }),
      let status = session.activities.first,
      status.type == .custom
    else { return nil }
    return status
  }

  var body: some View {
    let user = gw.user.currentUser
    let displayName = user?.global_name ?? user?.username ?? "Unknown User"
    let username = user?.username ?? "Unknown User"
    let status = currentCustomStatus
    HStack {
      Button {
        showingPopover.toggle()
      } label: {
        HStack {
          if let user {
            Profile.AvatarWithPresence(
              member: nil,
              user: user
            )
            .maxHeight(30)
            .profileAnimated(barHovered)
            .profileShowsAvatarDecoration()
          }

          VStack(alignment: .leading) {
            Text(displayName)
              .bold()
            if showingUsername {
              Text(verbatim: "@\(username)")
                .transition(.opacity)
            } else if let status {
              if let emoji = status.emoji {
                if let url = emojiURL(for: emoji, animated: true) {
                  AnimatedImage(url: url)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                } else {
                  Text(emoji.name)
                    .font(.subheadline)
                }
              }

              Text(status.state ?? "")
                .transition(.opacity)
            }
          }
          .background(.black.opacity(0.001))
          .onHover { showingUsername = $0 }
          .animation(.spring(), value: showingUsername)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Account: \(displayName)")
      .popover(isPresented: $showingPopover) {
        ProfileButtonPopout()
      }

      Spacer()

      #if os(macOS)
        Button {
          openWindow(id: "settings")
        } label: {
          Image(systemName: "gearshape.fill")
            .font(.title2)
            .padding(5)
        }
        .buttonStyle(.borderless)
      #elseif os(iOS)
        /// targetting ipad here, ios wouldnt have this at all
        // do something
      #endif
    }
    .padding(8)
    .background {
      if let nameplate = gw.user.currentUser?.collectibles?.nameplate {
        Profile.NameplateView(nameplate: nameplate)
          .nameplateAnimated(barHovered)
      }
    }
    .clipped()
    .onHover { barHovered = $0 }
  }

  func emojiURL(for emoji: Gateway.Activity.ActivityEmoji, animated: Bool)
    -> URL?
  {
    guard let id = emoji.id else { return nil }
    return URL(
      string: CDNEndpoint.customEmoji(emojiId: id).url
        + (animated && emoji.animated == true ? ".gif" : ".png") + "?size=44"
    )
  }

  struct ProfileButtonPopout: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @Environment(\.colorScheme) var systemColorScheme
    @State var statusSelectionExpanded = false
    @State var accountSelectionExpanded = false
    @State private var profile: DiscordUser.Profile?

    private var currentCustomStatus: Gateway.Activity? {
      guard
        let session = gw.user.sessions.first(where: { $0.id == "all" }),
        let status = session.activities.first,
        status.type == .custom
      else { return nil }
      return status
    }

    var resolvedColorScheme: ColorScheme? {
      guard let firstColor = profile?.user_profile?.theme_colors?.first else {
        return nil
      }
      return firstColor.asColor()?.suggestedColorScheme()
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        bannerView

        profileBody
          .padding()

        Divider()
          .padding(.horizontal)

        controlsBody
          .padding(.horizontal)
          .padding(.vertical, 8)
      }
      .frame(width: 320)
      .fixedSize(horizontal: false, vertical: true)
      .task(fetchProfile)
      .background(
        Profile.ThemeColorsBackground(
          colors: profile?.user_profile?.theme_colors
        )
        .overlay(.ultraThinMaterial)
      )
      .environment(\.colorScheme, resolvedColorScheme ?? systemColorScheme)
    }

    @ViewBuilder
    var bannerView: some View {
      if let user = gw.user.currentUser {
        Utils.UserBannerURL(
          user: user.toPartialUser(),
          profile: profile,
          mainProfileBanner: true,
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
                profile?.user_profile?.theme_colors?.first
                ?? profile?.user_profile?.accent_color
              Rectangle()
                .aspectRatio(3, contentMode: .fit)
                .foregroundStyle(color?.asColor() ?? Color.accentColor)
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
              member: nil,
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
    }

    @ViewBuilder
    var profileBody: some View {
      if let user = gw.user.currentUser {
        let profileMeta: DiscordUser.Profile.Metadata? = profile?.user_profile
        VStack(alignment: .leading, spacing: 6) {
          Text(user.global_name ?? user.username ?? "Unknown User")
            .font(.title2)
            .bold()
            .lineLimit(1)
            .minimumScaleFactor(0.5)

          FlowLayout(xSpacing: 8, ySpacing: 2) {
            Group {
              Text(verbatim: "@\(user.username ?? "unknown")")
              if let pronouns = profileMeta?.pronouns ?? user.pronouns,
                !pronouns.isEmpty
              {
                Text(verbatim: "•")
                Text(pronouns)
              }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Profile.BadgesView(profile: profile, user: user.toPartialUser())
          }

          if let status = currentCustomStatus {
            HStack(spacing: 6) {
              if let emoji = status.emoji {
                if let url = emojiURL(for: emoji, animated: true) {
                  AnimatedImage(url: url)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                } else {
                  Text(emoji.name)
                    .font(.subheadline)
                }
              }
              if let state = status.state, !state.isEmpty {
                Text(state)
                  .font(.subheadline)
              }
            }
            .padding(.top, 2)
          }

          if let bio = profileMeta?.bio, !bio.isEmpty {
            MarkdownText(content: bio)
              .equatable()
              .padding(.top, 4)
          }
        }
      }
    }

    @ViewBuilder
    var controlsBody: some View {
      VStack(alignment: .leading, spacing: 4) {
        Button {
        } label: {
          Label("Edit Profile", systemImage: "pencil")
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .disabled(true)

        DisclosureGroup(isExpanded: $statusSelectionExpanded) {
          let statuses: [Gateway.Status] = [
            .online,
            .afk,
            .doNotDisturb,
            .invisible,
          ]

          ForEach(statuses, id: \.self) { status in
            AsyncButton {
              await gw.presence.setPresence(status: status)
              gw.presence.currentClientStatus = status
              withAnimation {
                statusSelectionExpanded = false
              }
            } catch: { error in
              appState.error = error
            } label: {
              statusItem(status)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
          }
        } label: {
          Button {
            withAnimation {
              statusSelectionExpanded.toggle()
            }
          } label: {
            statusItem(gw.presence.currentClientStatus)
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.borderless)
        }

        DisclosureGroup(isExpanded: $accountSelectionExpanded) {
          ForEach(gw.accounts.accounts, id: \.id) { account in
            let isSignedInAccount = account.id == gw.accounts.currentAccountID
            AsyncButton {
              gw.accounts.currentAccountID = nil
              await gw.disconnectIfNeeded()
              gw.resetStores()
              gw.accounts.currentAccountID = account.id
            } catch: { error in
              appState.error = error
            } label: {
              HStack {
                Profile.AvatarWithPresence(
                  member: nil,
                  user: account.user
                )
                .maxWidth(25)
                .maxHeight(25)
                .profileAnimated(false)
                .profileShowsAvatarDecoration()

                VStack(alignment: .leading) {
                  Text(
                    account.user.global_name
                      ?? account.user.username
                  )
                  .lineSpacing(1)
                  .bold()
                  Text(verbatim: "@\(account.user.username)")
                    .lineSpacing(1)
                }

                Spacer()

                if isSignedInAccount {
                  Image(systemName: "checkmark")
                }
              }
              .padding(.vertical, 2)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(isSignedInAccount)
          }

          AsyncButton {
            gw.accounts.currentAccountID = nil
            await gw.disconnectIfNeeded()
            gw.resetStores()
          } catch: { error in
            appState.error = error
          } label: {
            Label("Add Account", systemImage: "person.crop.circle.badge.plus")
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.borderless)
        } label: {
          Button {
            withAnimation {
              accountSelectionExpanded.toggle()
            }
          } label: {
            Label("Switch Account", systemImage: "person.crop.circle")
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.borderless)
        }
      }
    }

    func emojiURL(for emoji: Gateway.Activity.ActivityEmoji, animated: Bool)
      -> URL?
    {
      guard let id = emoji.id else { return nil }
      return URL(
        string: CDNEndpoint.customEmoji(emojiId: id).url
          + (animated && emoji.animated == true ? ".gif" : ".png") + "?size=44"
      )
    }

    @Sendable
    func fetchProfile() async {
      guard profile == nil, let userID = gw.user.currentUser?.id else { return }
      let res = try? await gw.client.getUserProfile(
        userID: userID,
        withMutualGuilds: false,
        withMutualFriends: false,
        withMutualFriendsCount: false
      )
      do {
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

    @ViewBuilder
    func statusItem(_ status: Gateway.Status) -> some View {
      let color: Color = {
        switch status {
        case .online: return .init(hexadecimal6: 0x42a25a)
        case .afk: return .init(hexadecimal6: 0xca9653)
        case .doNotDisturb: return .init(hexadecimal6: 0xd83a42)
        default: return .init(hexadecimal6: 0x82838b)
        }
      }()

      Label {
        Text(status.rawValue.capitalized)
      } icon: {
        Group {
          switch status {
          case .online:
            StatusIndicatorShapes.OnlineShape()
          case .afk:
            StatusIndicatorShapes.IdleShape()
          case .doNotDisturb:
            StatusIndicatorShapes.DNDShape()
          default:
            StatusIndicatorShapes.InvisibleShape()
          }
        }
        .foregroundStyle(color)
        .frame(width: 15, height: 15)
      }
    }
  }

}

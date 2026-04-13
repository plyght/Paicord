//
//  MessageCell.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 07/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUIX

struct MessageCell: View {

  /// Controls the size of the avatar in the message cell.
  #if os(iOS)
    static let avatarSize: CGFloat = 40
  #elseif os(macOS)
    static let avatarSize: CGFloat = 35
  #endif

  static let doubleTapDefaultEmoji: String = "❤️"
  static let swipeReplyThreshold: CGFloat = 60
  static let swipeReplyMaxOffset: CGFloat = 90

  @Environment(\.gateway) var gw

  var message: DiscordChannel.Message
  var priorMessage: DiscordChannel.Message?
  var channelStore: ChannelStore
  var currentUserID: UserSnowflake?
  var currentUserRoles: [RoleSnowflake]?
  @State var cellHighlighted = false
  @State private var mentionPulse: Double = 0
  @State private var swipeOffset: CGFloat = 0
  @State private var swipeHapticFired = false
  @State private var showQuickReactions = false
  #if os(macOS)
    @State private var macSwipeState = CellSwipeState()
  #endif

  var effectiveSwipeOffset: CGFloat {
    #if os(macOS)
      return macSwipeState.offset
    #else
      return swipeOffset
    #endif
  }

  init(
    for message: DiscordChannel.Message,
    prior: DiscordChannel.Message? = nil,
    channel: ChannelStore,
    currentUserID: UserSnowflake? = nil,
    currentUserRoles: [RoleSnowflake]? = nil
  ) {
    self.message = message
    self.priorMessage = prior
    self.channelStore = channel
    self.currentUserID = currentUserID
    self.currentUserRoles = currentUserRoles
  }

  func reactWithDefaultEmoji() {
    reactWithUnicode(Self.doubleTapDefaultEmoji)
    ImpactGenerator.impact(style: .light)
  }

  func reactWithUnicode(_ emoji: String) {
    guard let reaction = try? Reaction.unicodeEmoji(emoji) else { return }
    let channelID = message.channel_id
    let messageID = message.id
    let client = gw.client
    Task {
      _ = try? await client.addMessageReaction(
        channelId: channelID,
        messageId: messageID,
        emoji: reaction,
        type: .normal
      ).guardSuccess()
    }
    RecentReactionsStore.shared.record(emoji)
  }

  func removeUnicodeReaction(_ emoji: String) {
    guard let reaction = try? Reaction.unicodeEmoji(emoji) else { return }
    let channelID = message.channel_id
    let messageID = message.id
    let client = gw.client
    Task {
      _ = try? await client.deleteOwnMessageReaction(
        channelId: channelID,
        messageId: messageID,
        emoji: reaction,
        type: .normal
      ).guardSuccess()
    }
  }

  func toggleUnicodeReaction(_ emoji: String) {
    if appliedUnicodeEmojis.contains(emoji) {
      removeUnicodeReaction(emoji)
    } else {
      reactWithUnicode(emoji)
    }
  }

  var appliedUnicodeEmojis: Set<String> {
    guard let reactions = channelStore.reactions[message.id] else { return [] }
    var out: Set<String> = []
    for (emoji, reaction) in reactions where reaction.selfReacted {
      if emoji.id == nil, let name = emoji.name {
        out.insert(name)
      }
    }
    return out
  }

  func beginReply() {
    let vm = ChatView.InputBar.vm(for: channelStore)
    vm.messageAction = .reply(message: message, mention: true)
  }

  var userMentioned: Bool {
    guard let currentUserID else { return false }
    let explicit = message.mentions.contains(where: { $0.id == currentUserID })
    if channelStore.channel?.type == .dm || channelStore.channel?.type == .groupDm {
      return explicit
    }
    if explicit { return true }
    if message.mention_everyone { return true }
    if let currentUserRoles {
      for roleID in message.mention_roles {
        if currentUserRoles.contains(roleID) {
          return true
        }
      }
    }
    return false
  }

  var body: some View {
    let inline =
      priorMessage?.author?.id == message.author?.id
      && message.timestamp.date.timeIntervalSince(
        priorMessage?.timestamp.date ?? .distantPast
      ) < 300 && message.referenced_message == nil
      && message.type == .default

    ZStack(alignment: .leading) {
      let progress = min(1, effectiveSwipeOffset / Self.swipeReplyThreshold)
      Image(systemName: "arrowshape.turn.up.left.fill")
        .font(.title3)
        .foregroundStyle(.secondary)
        .opacity(Double(progress))
        .scaleEffect(0.6 + 0.4 * progress)
        .padding(.leading, 12)
        .allowsHitTesting(false)

      Group {
        // Content
        switch message.type {
        case .default, .reply:
          DefaultMessage(
            message: message,
            channelStore: channelStore,
            inline: inline
          )
          .equatable()
        case .chatInputCommand:
          ChatInputCommandMessage(message: message, channelStore: channelStore)
            .equatable()
        default:
          HStack {
            AvatarBalancing()
            (Text(Image(systemName: "xmark.circle.fill"))
              + Text(" Unsupported message type \(message.type)"))
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .offset(x: effectiveSwipeOffset)
    }
    .background(Color.almostClear)
    .padding(.horizontal, 10)
    .padding(.vertical, 2)
    .highPriorityGesture(
      TapGesture(count: 2).onEnded {
        reactWithDefaultEmoji()
      }
    )
    .highPriorityGesture(
      LongPressGesture(minimumDuration: 0.35).onEnded { _ in
        ImpactGenerator.impact(style: .medium)
        showQuickReactions = true
      }
    )
    .popover(isPresented: $showQuickReactions, arrowEdge: .top) {
      QuickReactionPicker(applied: appliedUnicodeEmojis) { emoji in
        showQuickReactions = false
        toggleUnicodeReaction(emoji)
      }
      .presentationCompactAdaptation(.popover)
      .presentationBackground(.clear)
    }
    #if os(iOS)
      .simultaneousGesture(
        DragGesture(minimumDistance: 15)
          .onChanged { value in
            guard abs(value.translation.width) > abs(value.translation.height)
            else { return }
            let raw = max(0, value.translation.width)
            let damped = min(Self.swipeReplyMaxOffset, raw * 0.7)
            swipeOffset = damped
            if !swipeHapticFired && damped >= Self.swipeReplyThreshold {
              swipeHapticFired = true
              ImpactGenerator.impact(style: .medium)
            }
          }
          .onEnded { value in
            let triggered = swipeOffset >= Self.swipeReplyThreshold
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
              swipeOffset = 0
            }
            swipeHapticFired = false
            if triggered {
              beginReply()
            }
          }
      )
    #endif
    .overlay {
      if userMentioned {
        Color.accentColor.opacity(mentionPulse * 0.18)
          .allowsHitTesting(false)
      }
    }
    .overlay(alignment: .leading) {
      if userMentioned {
        Color.accentColor.opacity(mentionPulse)
          .frame(width: 2)
          .allowsHitTesting(false)
      }
    }
    .onAppear {
      guard userMentioned else { return }
      mentionPulse = 0
      withAnimation(.easeOut(duration: 0.25)) { mentionPulse = 1 }
      withAnimation(.easeIn(duration: 1.1).delay(0.35)) { mentionPulse = 0 }
    }
    #if os(macOS)
      .onHover { hovered in
        self.cellHighlighted = hovered
        if hovered {
          let state = self.macSwipeState
          let commit: () -> Void = { self.beginReply() }
          MacScrollMonitor.shared.active = { event in
            state.handle(
              event,
              threshold: Self.swipeReplyThreshold,
              maxOffset: Self.swipeReplyMaxOffset,
              onCommit: commit
            )
          }
        } else if !self.macSwipeState.tracking {
          MacScrollMonitor.shared.active = nil
        }
      }
      .background(
        cellHighlighted
          ? Color(NSColor.secondaryLabelColor).opacity(0.1) : .clear
      )
    #endif
    .entityContextMenu(for: message)
    .padding(.top, inline ? 0 : 15)  // adds space between message groups
  }
}

#Preview {
  let llsc12 = DiscordUser(
    id: .init("381538809180848128"),
    username: "llsc12",
    discriminator: "0",
    global_name: nil,
    avatar: "df71b3f223666fd8331c9940c6f7cbd9",
    banner: nil,
    bot: false,
    system: false,
    mfa_enabled: true,
    accent_color: nil,
    locale: .englishUS,
    verified: true,
    email: nil,
    flags: .init(rawValue: 4_194_352),
    premium_type: nil,
    public_flags: .init(rawValue: 4_194_304),
    avatar_decoration_data: nil
  )
  MessageCell(
    for: .init(
      id: try! .makeFake(),
      channel_id: try! .makeFake(),
      author: llsc12,
      content: "gm",
      timestamp: .init(date: .now),
      edited_timestamp: nil,
      tts: false,
      mention_everyone: false,
      mentions: [],
      mention_roles: [],
      mention_channels: nil,
      attachments: [],
      embeds: [],
      reactions: nil,
      nonce: nil,
      pinned: false,
      webhook_id: nil,
      type: DiscordChannel.Message.Kind.default,
      activity: nil,
      application: nil,
      application_id: nil,
      message_reference: nil,
      flags: [],
      referenced_message: nil,
      interaction: nil,
      thread: nil,
      components: nil,
      sticker_items: nil,
      stickers: nil,
      position: nil,
      role_subscription_data: nil,
      resolved: nil,
      poll: nil,
      call: nil,
      guild_id: nil,
      member: nil
    ),
    prior: nil,
    channel: .init(id: try! .makeFake())
  )
}

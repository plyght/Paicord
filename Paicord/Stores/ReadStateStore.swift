//
//  ReadStateStore.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 20/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import PaicordLib
#if canImport(UserNotifications)
  import UserNotifications
#endif

@Observable
class ReadStateStore: DiscordDataStore {
  @ObservationIgnored
  var gateway: GatewayStore?

  @ObservationIgnored
  var eventTask: Task<Void, Never>?

  func setGateway(_ gateway: GatewayStore?) {
    self.gateway = gateway
    setupEventHandling()
  }

  var readStates: [AnySnowflake: Gateway.ReadState] = [:]

  /// Channels with at least one unread message since the user's last ack.
  /// Tracked locally on top of READY-provided read states so the UI updates live.
  var unreadChannels: Set<ChannelSnowflake> = []

  /// Per-channel mention counts that the current user is the target of.
  var mentionCounts: [ChannelSnowflake: Int] = [:]

  /// Per-channel last seen message id from incoming MESSAGE_CREATE events.
  /// Used to send a correct ack payload.
  var latestMessageIds: [ChannelSnowflake: MessageSnowflake] = [:]

  /// Reverse index so aggregate queries don't need a loaded GuildStore.
  var channelToGuild: [ChannelSnowflake: GuildSnowflake] = [:]

  /// Channels currently visible in some window. Populated by ChatView.
  @ObservationIgnored
  var focusedChannels: Set<ChannelSnowflake> = []

  func setupEventHandling() {
    eventTask?.cancel()
    guard let gateway = gateway?.gateway else { return }
    eventTask = Task { @MainActor in
      for await event in await gateway.events {
        switch event.data {
        case .ready(let readyData):
          handleReady(readyData)
        case .messageAcknowledge(let ackData):
          handleMessageAcknowledge(ackData)
        case .messageCreate(let message):
          handleMessageCreate(message)
        default:
          break
        }
      }
    }
  }

  private func handleReady(_ readyData: Gateway.Ready) {
    readStates = (readyData.read_state ?? []).reduce(into: [:]) {
      $0[$1.id] = $1
    }
    // Seed mention counts and unread set from server-side read state
    unreadChannels.removeAll(keepingCapacity: true)
    mentionCounts.removeAll(keepingCapacity: true)
    channelToGuild.removeAll(keepingCapacity: true)
    for guild in readyData.guilds {
      for channel in guild.channels ?? [] {
        channelToGuild[channel.id] = guild.id
      }
    }
    for state in readyData.read_state ?? [] {
      let channelId = ChannelSnowflake(state.id.rawValue)
      if let mention = state.mention_count, mention > 0 {
        mentionCounts[channelId] = mention
      }
      if let last = state.last_message_id,
        let acked = state.last_acked_id,
        last.rawValue > acked.rawValue
      {
        unreadChannels.insert(channelId)
      }
    }
  }

  private func handleMessageAcknowledge(
    _ ackData: Gateway.MessageAcknowledge
  ) {
    // Server confirms an ack — clear our local mirror. The payload is sparse so
    // we resync any channel whose last_acked we know about.
    // The Discord ack event doesn't carry a channel id directly in this struct,
    // so we rely on local markChannelRead to clear state optimistically.
  }

  private func handleMessageCreate(_ message: Gateway.MessageCreate) {
    let channelId = message.channel_id
    latestMessageIds[channelId] = message.id
    if let guildId = message.guild_id {
      channelToGuild[channelId] = guildId
    }

    let currentUserId = gateway?.user.currentUser?.id
    // Don't mark our own messages as unread/mention.
    if message.author?.id == currentUserId {
      markChannelRead(
        channelId: channelId,
        lastMessageId: message.id,
        sendAck: false
      )
      return
    }

    // If the user is currently viewing this channel, auto-ack.
    if focusedChannels.contains(channelId) {
      markChannelRead(
        channelId: channelId,
        lastMessageId: message.id,
        sendAck: true
      )
      return
    }

    let level = effectiveNotificationLevel(
      guildId: message.guild_id,
      channelId: channelId
    )
    let isMention = isMentioningCurrentUser(
      message: message,
      currentUserId: currentUserId
    )

    // Unread tracking — respect "noMessages" override (still no badge then).
    if level != .noMessages {
      unreadChannels.insert(channelId)
    }

    if isMention {
      mentionCounts[channelId, default: 0] += 1
      postMentionNotification(for: message)
    }
  }

  // MARK: - Public Query API

  func unreadCount(for channelId: ChannelSnowflake) -> Int {
    mentionCounts[channelId] ?? 0
  }

  func hasUnread(for channelId: ChannelSnowflake) -> Bool {
    unreadChannels.contains(channelId)
  }

  func hasMention(for channelId: ChannelSnowflake) -> Bool {
    (mentionCounts[channelId] ?? 0) > 0
  }

  func aggregateDMMentions() -> Int {
    guard let dms = gateway?.user.privateChannels else { return 0 }
    var total = 0
    for channelId in dms.keys {
      total += mentionCounts[channelId] ?? 0
    }
    return total
  }

  func aggregateDMHasUnread() -> Bool {
    guard let dms = gateway?.user.privateChannels else { return false }
    for channelId in dms.keys where unreadChannels.contains(channelId) {
      return true
    }
    return false
  }

  func aggregateMentions(for guild: GuildStore) -> Int {
    var total = 0
    for channelId in guild.channels.keys {
      total += mentionCounts[channelId] ?? 0
    }
    return total
  }

  func aggregateHasUnread(for guild: GuildStore) -> Bool {
    for channelId in guild.channels.keys
    where unreadChannels.contains(channelId) {
      // Skip muted channels/guild
      if isMuted(guildId: guild.guildId, channelId: channelId) { continue }
      return true
    }
    return false
  }

  /// Guild-id variant that doesn't require a loaded GuildStore. Used by the
  /// sidebar, which renders badges for guilds the user hasn't opened yet.
  func aggregateMentions(for guildId: GuildSnowflake) -> Int {
    var total = 0
    for (channelId, gid) in channelToGuild where gid == guildId {
      total += mentionCounts[channelId] ?? 0
    }
    return total
  }

  func aggregateHasUnread(for guildId: GuildSnowflake) -> Bool {
    for (channelId, gid) in channelToGuild
    where gid == guildId && unreadChannels.contains(channelId) {
      if isMuted(guildId: guildId, channelId: channelId) { continue }
      return true
    }
    return false
  }

  // MARK: - Marking read

  func markChannelRead(
    channelId: ChannelSnowflake,
    lastMessageId: MessageSnowflake?,
    sendAck: Bool
  ) {
    unreadChannels.remove(channelId)
    mentionCounts.removeValue(forKey: channelId)
    let messageId = lastMessageId ?? latestMessageIds[channelId]
    if sendAck, let messageId {
      Task { await sendAckRequest(channelId: channelId, messageId: messageId) }
    }
  }

  func markAllRead() {
    let snapshot = unreadChannels.union(mentionCounts.keys)
    for channelId in snapshot {
      let lastMessageId = latestMessageIds[channelId]
        ?? readStates[AnySnowflake(channelId.rawValue)]?.last_message_id
        .map { MessageSnowflake($0.rawValue) }
      markChannelRead(
        channelId: channelId,
        lastMessageId: lastMessageId,
        sendAck: lastMessageId != nil
      )
    }
  }

  func setFocused(_ channelId: ChannelSnowflake, focused: Bool) {
    if focused {
      focusedChannels.insert(channelId)
      markChannelRead(
        channelId: channelId,
        lastMessageId: latestMessageIds[channelId],
        sendAck: true
      )
    } else {
      focusedChannels.remove(channelId)
    }
  }

  // MARK: - Ack network

  private func sendAckRequest(
    channelId: ChannelSnowflake,
    messageId: MessageSnowflake
  ) async {
    guard let token = gateway?.accounts.currentAccount?.token.value else {
      return
    }
    let urlString =
      "https://discord.com/api/v9/channels/\(channelId.rawValue)/messages/\(messageId.rawValue)/ack"
    guard let url = URL(string: urlString) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(token, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = ["token": NSNull(), "manual": false]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      _ = try await URLSession.shared.data(for: request)
    } catch {
      print("[ReadStateStore] ack failed: \(error)")
    }
  }

  // MARK: - Notification settings

  private enum NotificationLevel {
    case allMessages
    case onlyMentions
    case noMessages
  }

  private func effectiveNotificationLevel(
    guildId: GuildSnowflake?,
    channelId: ChannelSnowflake
  ) -> NotificationLevel {
    guard let settings = gateway?.userGuildSettings.userGuildSettings[guildId]
    else { return .allMessages }

    if settings.muted { return .noMessages }

    if let override = settings.channel_overrides.first(where: {
      $0.channel_id == channelId
    }) {
      if override.muted { return .noMessages }
      switch override.message_notifications {
      case .allMessages: return .allMessages
      case .onlyMentions: return .onlyMentions
      case .noMessages: return .noMessages
      default: break
      }
    }

    switch settings.message_notifications {
    case 0: return .allMessages
    case 1: return .onlyMentions
    case 2: return .noMessages
    default: return .allMessages
    }
  }

  private func isMuted(
    guildId: GuildSnowflake?,
    channelId: ChannelSnowflake
  ) -> Bool {
    guard let settings = gateway?.userGuildSettings.userGuildSettings[guildId]
    else { return false }
    if settings.muted { return true }
    if let override = settings.channel_overrides.first(where: {
      $0.channel_id == channelId
    }), override.muted {
      return true
    }
    return false
  }

  private func isMentioningCurrentUser(
    message: Gateway.MessageCreate,
    currentUserId: UserSnowflake?
  ) -> Bool {
    guard let currentUserId else { return false }

    let settings = gateway?.userGuildSettings.userGuildSettings[message.guild_id]

    // Direct user mention
    if message.mentions.contains(where: { $0.id == currentUserId }) {
      return true
    }

    // @everyone / @here
    if message.mention_everyone, settings?.suppress_everyone != true {
      return true
    }

    // Role mention
    if !message.mention_roles.isEmpty,
      settings?.suppress_roles != true,
      let guildId = message.guild_id,
      let guildStore = gateway?.peekGuildStore(for: guildId),
      let userRoles = guildStore.members[currentUserId]?.roles
    {
      let userRoleSet = Set(userRoles)
      if message.mention_roles.contains(where: { userRoleSet.contains($0) }) {
        return true
      }
    }

    // DMs always count as mentions for notification purposes
    if message.guild_id == nil { return true }

    return false
  }

  // MARK: - System notifications

  private func postMentionNotification(for message: Gateway.MessageCreate) {
    #if canImport(UserNotifications)
      let center = UNUserNotificationCenter.current()
      let content = UNMutableNotificationContent()
      let authorName =
        message.author?.global_name ?? message.author?.username ?? "Someone"
      content.title = authorName
      content.body =
        message.content.isEmpty ? "(attachment)" : message.content
      content.sound = .default
      content.userInfo = [
        "channel_id": message.channel_id.rawValue,
        "guild_id": message.guild_id?.rawValue ?? "",
        "message_id": message.id.rawValue,
      ]
      let request = UNNotificationRequest(
        identifier: message.id.rawValue,
        content: content,
        trigger: nil
      )
      center.add(request) { _ in }
    #endif
  }
}

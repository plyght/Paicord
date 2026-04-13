//
//  GatewayStore.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 06/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import PaicordLib

@Observable
final class GatewayStore {
  static let shared = GatewayStore()

  // Some setup for the gateway
  @ObservationIgnored var captchaCallback: CaptchaChallengeHandler?
  @ObservationIgnored var mfaCallback: MFAVerificationHandler?
  @ObservationIgnored private(set) var gateway: UserGatewayManager?

  @ObservationIgnored
  var client: DiscordClient {
    gateway?.client ?? unauthenticatedClient
  }

  @ObservationIgnored
  lazy var unauthenticatedClient: DefaultDiscordClient = {
    DefaultDiscordClient(
      captchaCallback: captchaCallback,
      mfaCallback: mfaCallback
    )
  }()

  var state: GatewayState = .noConnection {
    didSet {
    }
  }

  @ObservationIgnored
  var eventTask: Task<Void, Never>? = nil
  @ObservationIgnored
  var errorTask: Task<Void, Never>? = nil

  // MARK: - Gateway Management

  /// Disconnects current gateway and cancels event task if needed
  func disconnectIfNeeded() async {
    guard !([.stopped, .noConnection].contains(state)) else { return }
    await gateway?.disconnect()
    eventTask?.cancel()
    eventTask = nil
  }

  /// Connects to the gateway if it is not already connected
  func connectIfNeeded() async {
    guard [.stopped, .noConnection].contains(state), eventTask == nil else {
      return
    }
    if let account = accounts.currentAccount {
      await logIn(as: account)
    }
  }

  /// Login with a specific token
  func logIn(as account: TokenStore.AccountData) async {
    await disconnectIfNeeded()
    guard !ProcessInfo.isRunningInXcodePreviews else {
      // don't connect from previews
      return
    }
    gateway = await UserGatewayManager(
      token: account.token,
      captchaCallback: captchaCallback,
      mfaCallback: mfaCallback,
      stateCallback: { [weak self] state in
        Task { @MainActor in
          self?.state = state
        }
      }
    )
    setupEventHandling()
    await gateway?.connect()
  }

  /// Disconnects from the gateway. You must remove the current account from TokenStore before calling this.
  /// This will reset all stores.
  func logOut() async {
    await disconnectIfNeeded()
    gateway = nil
    resetStores()
  }

  func setupEventHandling() {
    eventTask = Task { @MainActor in
      guard let gateway else { return }
      for await event in await gateway.events {
        switch event.data {
        case .ready(let readyData):
          handleReady(readyData)
        case .voiceServerUpdate(let update):
          Task { await voice.handleVoiceServerUpdate(update) }
        case .voiceStateUpdate(let state):
          if state.user_id == user.currentUser?.id {
            voice.handleOwnVoiceStateUpdate(state)
          }
          voice.handleParticipantVoiceStateUpdate(state)
        case .callCreate(let call):
          handleCallCreate(call)
        case .callUpdate(let call):
          handleCallUpdate(call)
        case .callDelete(let call):
          handleCallDelete(call)
        default: break
        }
      }
    }

    errorTask = Task { @MainActor in
      guard let gateway else { return }
      for await (error, buffer) in await gateway.eventFailures {
        _ = (error, buffer)
      }
    }

    // Set up stores with gateway
    user.setGateway(self)
    settings.setGateway(self)
    userGuildSettings.setGateway(self)
    readStates.setGateway(self)
    presence.setGateway(self)
    messageDrain.setGateway(self)
    switcher.setGateway(self)
    voice.gateway = self

    // Update existing channel stores
    for channelStore in channels.values {
      channelStore.setGateway(self)
    }

    // Update existing guild stores
    for guildStore in guilds.values {
      guildStore.setGateway(self)
    }
  }

  func resetStores() {
    Task { await voice.disconnect() }
    user = .init()
    settings = .init()
    userGuildSettings = .init()
    readStates = .init()
    presence = .init()
    messageDrain = .init()
    switcher = .init()
    voice = .init()
    channels = [:]
    guilds = [:]
    subscribedGuilds = []
  }

  // MARK: - Data Stores

  let accounts = TokenStore()
  var user = CurrentUserStore()
  var userGuildSettings = UserGuildSettingsStore()
  var readStates = ReadStateStore()
  var settings = SettingsStore()
  let externalBadges = ExternalBadgeStore()
  var presence = PresenceStore()
  var messageDrain = MessageDrainStore()
  var switcher = QuickSwitcherProviderStore()
  var voice = VoiceStore()

  private var channels: [ChannelSnowflake: ChannelStore] = [:]
  func getChannelStore(for id: ChannelSnowflake, from guild: GuildStore? = nil)
    -> ChannelStore
  {
    if let store = channels[id] {
      return store
    } else {
      let channel = guild?.channels[id] ?? user.privateChannels[id]
      let store = ChannelStore(id: id, from: channel, guildStore: guild)
      store.setGateway(self)
      channels[id] = store
      return store
    }
  }

  private var subscribedGuilds: Set<GuildSnowflake> = []
  private var guilds: [GuildSnowflake: GuildStore] = [:]

  /// Read-only peek into the guild store map for stores that need to look up
  /// member roles without triggering the subscription side-effects of `getGuildStore`.
  func peekGuildStore(for id: GuildSnowflake) -> GuildStore? {
    guilds[id]
  }

  func getGuildStore(for id: GuildSnowflake) -> GuildStore {
    defer {
      if !subscribedGuilds.contains(id) {
        subscribedGuilds.insert(id)
        Task {
          await gateway?.updateGuildSubscriptions(
            payload:
              .init(subscriptions: [  // dict of guilds to subscriptions
                id: .init(
                  typing: true,
                  activities: false,
                  threads: true,
                  member_updates: true,
                  channels: [:],
                  thread_member_lists: nil
                )
              ])
          )
        }
      }
    }
    if let store = guilds[id] {
      return store
    } else {
      let guild = user.guilds[id]
      let store = GuildStore(id: id, from: guild)
      store.setGateway(self)
      guilds[id] = store
      return store
    }
  }

  // MARK: - Call Tracking

  var activeCall: ActiveCallInfo?

  struct ActiveCallInfo {
    var channelId: ChannelSnowflake
    var messageId: MessageSnowflake
    var region: String
    var ringing: [UserSnowflake]
  }

  private func handleCallCreate(_ call: Gateway.CallCreate) {
    activeCall = ActiveCallInfo(
      channelId: call.channel_id,
      messageId: call.message_id,
      region: call.region,
      ringing: call.ringing
    )
  }

  private func handleCallUpdate(_ call: Gateway.CallUpdate) {
    activeCall = ActiveCallInfo(
      channelId: call.channel_id,
      messageId: call.message_id,
      region: call.region,
      ringing: call.ringing
    )
  }

  private func handleCallDelete(_ call: Gateway.CallDelete) {
    if activeCall?.channelId == call.channel_id {
      activeCall = nil
    }
  }

  // MARK: - Handlers

  private func handleReady(_ data: Gateway.Ready) {
    // Send initial voice state (not in any channel)
    Task {
      await self.gateway?.updateVoiceState(
        payload: .init(
          guild_id: nil,
          channel_id: nil,
          self_mute: voice.isMuted,
          self_deaf: voice.isDeafened,
          self_video: false,
          preferred_region: nil,
          preferred_regions: nil,
          flags: []
        )
      )
    }

    // update user data in account storage
    accounts.updateProfile(for: data.user.id, data.user)

    // if we have subscribed guilds, we need to clear out non-focused channel stores
    guard self.subscribedGuilds.isEmpty == false else { return }
    let channelIds = PaicordAppState.instances.compactMap(
      \.value.selectedChannel
    )
    channels = channels.filter { channelIds.contains($0.key) }
    if let channel = channels.values.first {
      channel.messages.removeAll()
      Task { @MainActor in
        defer {
          NotificationCenter.default.post(
            name: .chatViewShouldScrollToBottom,
            object: ["channelId": channel.channelId]
          )
        }
        do {
          try await channel.fetchMessages()
        } catch {
          PaicordAppState.instances.first?.value.error = error
        }
      }
    }
    var previousSubscribedGuilds = self.subscribedGuilds
    // remove values from previousSubscribedGuilds that don't exist anymore
    let existingGuildIds = Set(data.guilds.map(\.id))
    previousSubscribedGuilds = previousSubscribedGuilds.filter {
      existingGuildIds.contains($0)
    }

    self.subscribedGuilds = []
    // dont subscribing only to focused guilds. resubscribe to all previous guilds
    for guildId in previousSubscribedGuilds {
      _ = getGuildStore(for: guildId)
    }
    //    // get all active window states, and get their selected guilds to resubscribe to guilds that are open
    //    PaicordAppState.instances.compactMap(\.value.selectedGuild).forEach {
    //      guildId in
    //      _ = getGuildStore(for: guildId)
    //    }

    // Now that we've done that, we need to use this ready data to update any internal stores that need it
    // guilds need repopulating. also guilds could have been left during the client down time. remove guilds if they don't exist anymore then repopulate.
    // remove guilds that don't exist anymore, also remove their guildstores and any of their channelstores
    for (guildId, guildStore) in guilds {
      if !existingGuildIds.contains(guildId) {
        // remove their channels from channel stores
        for channelId in guildStore.channels.keys {
          channels.removeValue(forKey: channelId)  // only really removes anything if the server that disappeared had a focused channel
        }
        // remove the guildstore itself
        guilds.removeValue(forKey: guildId)
      }
    }

    // repopulate guildstores
    let guildMap = Dictionary(uniqueKeysWithValues: data.guilds.map { ($0.id, $0) })
    for guildStore in self.guilds.values {
      if let guild = guildMap[guildStore.guildId] {
        guildStore.populate(with: guild)
      }
    }

  }
}

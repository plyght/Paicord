//
//  VoiceStore.swift
//  Paicord
//
//  Manages the voice connection lifecycle, audio capture/playback,
//  and provides observable state for the UI.
//

import AsyncHTTPClient
import Foundation
import NIO
import PaicordLib
import SwiftUI

@Observable
final class VoiceStore: @unchecked Sendable {
  @ObservationIgnored
  weak var gateway: GatewayStore?

  // MARK: - Connection State

  enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
  }

  var connectionState: ConnectionState = .disconnected
  var connectedChannelId: ChannelSnowflake?
  var connectedGuildId: GuildSnowflake?
  var connectedChannelName: String?
  var connectedGuildName: String?

  // MARK: - Audio State

  var isMuted = false
  var isDeafened = false
  var isSpeaking = false
  var selfVideoRequested = false

  /// SSRCs of users currently speaking
  var speakingUsers: Set<UInt32> = []

  /// Live voice states for users currently in the same call channel as us.
  /// Populated via `VOICE_STATE_UPDATE` and used to render real participant
  /// tiles (and to shrink the call stage when people don't pick up).
  var participants: [UserSnowflake: VoiceState] = [:]

  // MARK: - Voice connection objects

  @ObservationIgnored
  private var voiceConnection: VoiceConnection?
  @ObservationIgnored
  private var audioManager: AudioManager?
  @ObservationIgnored
  private var audioSendTask: Task<Void, Never>?
  @ObservationIgnored
  private let ringPlayer = CallRingPlayer()
  @ObservationIgnored
  private var ringTimeoutTask: Task<Void, Never>?
  let camera = CameraManager()

  // MARK: - Pending connection data

  @ObservationIgnored
  private var pendingSessionId: String?
  @ObservationIgnored
  private var pendingVoiceToken: String?
  @ObservationIgnored
  private var pendingEndpoint: String?
  @ObservationIgnored
  private var pendingGuildId: GuildSnowflake?

  // MARK: - Public API

  /// Join a guild voice channel.
  @MainActor
  func joinChannel(
    channelId: ChannelSnowflake,
    guildId: GuildSnowflake?,
    channelName: String?,
    guildName: String?,
    selfVideo: Bool = false
  ) async {
    guard connectionState == .disconnected || connectionState != .connecting else { return }

    let micGranted = await AudioManager.requestMicrophoneAccess()
    guard micGranted else {
      connectionState = .failed("Microphone access denied")
      return
    }

    connectionState = .connecting
    connectedChannelId = channelId
    connectedGuildId = guildId
    connectedChannelName = channelName
    connectedGuildName = guildName
    selfVideoRequested = selfVideo

    pendingGuildId = guildId
    participants.removeAll()
    ringPlayer.start()
    ringTimeoutTask?.cancel()
    ringTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(30))
      guard !Task.isCancelled else { return }
      await MainActor.run { self?.ringPlayer.stop() }
    }
    if selfVideo {
      camera.start()
    }

    await gateway?.gateway?.updateVoiceState(
      payload: .init(
        guild_id: guildId,
        channel_id: channelId,
        self_mute: isMuted,
        self_deaf: isDeafened,
        self_video: selfVideo
      )
    )
  }

  /// Disconnect from voice.
  @MainActor
  func disconnect() async {
    ringTimeoutTask?.cancel()
    ringTimeoutTask = nil
    ringPlayer.stop()
    camera.stop()
    audioSendTask?.cancel()
    audioSendTask = nil
    audioManager?.stopCapture()
    audioManager?.stopPlayback()
    audioManager = nil
    participants.removeAll()
    selfVideoRequested = false
    await voiceConnection?.disconnect()
    voiceConnection = nil

    await gateway?.gateway?.updateVoiceState(
      payload: .init(
        guild_id: connectedGuildId,
        channel_id: nil,
        self_mute: false,
        self_deaf: false,
        self_video: false
      )
    )

    connectionState = .disconnected
    connectedChannelId = nil
    connectedGuildId = nil
    connectedChannelName = nil
    connectedGuildName = nil
    speakingUsers.removeAll()
    isSpeaking = false
    pendingSessionId = nil
    pendingVoiceToken = nil
    pendingEndpoint = nil
    pendingGuildId = nil
  }

  /// Toggle mute state.
  @MainActor
  func toggleMute() async {
    isMuted.toggle()

    if isMuted {
      audioManager?.stopCapture()
      isSpeaking = false
      await voiceConnection?.setSpeaking(false)
    } else if connectionState == .connected {
      try? audioManager?.startCapture()
    }

    await voiceConnection?.setMuted(isMuted)

    if let guildId = connectedGuildId, let channelId = connectedChannelId {
      await gateway?.gateway?.updateVoiceState(
        payload: .init(
          guild_id: guildId,
          channel_id: channelId,
          self_mute: isMuted,
          self_deaf: isDeafened,
          self_video: false
        )
      )
    }
  }

  /// Toggle deafen state.
  @MainActor
  func toggleDeafen() async {
    isDeafened.toggle()
    if isDeafened {
      isMuted = true
      audioManager?.stopCapture()
      audioManager?.stopPlayback()
      isSpeaking = false
    } else {
      if connectionState == .connected {
        try? audioManager?.startPlayback()
        if !isMuted {
          try? audioManager?.startCapture()
        }
      }
    }

    await voiceConnection?.setDeafened(isDeafened)
    await voiceConnection?.setMuted(isMuted)

    if let guildId = connectedGuildId, let channelId = connectedChannelId {
      await gateway?.gateway?.updateVoiceState(
        payload: .init(
          guild_id: guildId,
          channel_id: channelId,
          self_mute: isMuted,
          self_deaf: isDeafened,
          self_video: false
        )
      )
    }
  }

  /// Toggle local camera capture + self_video flag.
  @MainActor
  func toggleVideo() async {
    selfVideoRequested.toggle()
    if selfVideoRequested {
      camera.start()
    } else {
      camera.stop()
    }
    if let channelId = connectedChannelId {
      await gateway?.gateway?.updateVoiceState(
        payload: .init(
          guild_id: connectedGuildId,
          channel_id: channelId,
          self_mute: isMuted,
          self_deaf: isDeafened,
          self_video: selfVideoRequested
        )
      )
    }
  }

  // MARK: - Gateway Event Handlers

  /// Called for every VOICE_STATE_UPDATE event. Tracks the set of users in
  /// the same call channel as us so the UI can render real participant tiles.
  @MainActor
  func handleParticipantVoiceStateUpdate(_ state: VoiceState) {
    guard let connectedChannelId else { return }
    if state.channel_id == connectedChannelId {
      participants[state.user_id] = state
    } else if participants[state.user_id] != nil {
      participants.removeValue(forKey: state.user_id)
    }
  }

  /// Called when the main gateway receives VOICE_SERVER_UPDATE.
  @MainActor
  func handleVoiceServerUpdate(_ update: Gateway.VoiceServerUpdate) async {
    pendingVoiceToken = update.token
    pendingEndpoint = update.endpoint

    await tryEstablishVoiceConnection()
  }

  /// Called when the main gateway receives VOICE_STATE_UPDATE for the current user.
  @MainActor
  func handleOwnVoiceStateUpdate(_ state: VoiceState) {
    pendingSessionId = state.session_id

    if state.channel_id == nil {
      Task { await disconnect() }
    }
  }

  // MARK: - Internal Connection Logic

  @MainActor
  private func tryEstablishVoiceConnection() async {
    let resolvedSessionId: String? = if let pending = pendingSessionId {
      pending
    } else {
      await gateway?.gateway?.getSessionID()
    }

    guard let token = pendingVoiceToken,
      let endpoint = pendingEndpoint,
      let sessionId = resolvedSessionId,
      let userId = gateway?.user.currentUser?.id.rawValue
    else {
      return
    }

    let connection = VoiceConnection(
      eventLoopGroup: HTTPClient.shared.eventLoopGroup,
      stateCallback: { [weak self] state in
        Task { @MainActor [weak self] in
          guard let self else { return }
          switch state {
          case .connected:
            self.ringTimeoutTask?.cancel()
            self.ringTimeoutTask = nil
            self.ringPlayer.stop()
            self.connectionState = .connected
            self.startAudio()
          case .disconnected:
            self.ringTimeoutTask?.cancel()
            self.ringTimeoutTask = nil
            self.ringPlayer.stop()
            if self.connectionState != .disconnected {
              self.connectionState = .disconnected
            }
          case .connecting, .waitingForServer, .connectingVoiceGateway,
            .performingIPDiscovery, .selectingProtocol:
            self.connectionState = .connecting
          case .failed(let reason):
            self.ringTimeoutTask?.cancel()
            self.ringTimeoutTask = nil
            self.ringPlayer.stop()
            self.connectionState = .failed(reason)
          }
        }
      }
    )

    self.voiceConnection = connection

    await connection.handleVoiceServerUpdate(
      token: token,
      endpoint: endpoint,
      guildId: pendingGuildId,
      channelId: connectedChannelId ?? ChannelSnowflake("0"),
      sessionId: sessionId,
      userId: userId
    )
  }

  @MainActor
  private func startAudio() {
    let manager = AudioManager()
    self.audioManager = manager

    if !isDeafened {
      try? manager.startPlayback()
    }

    if !isMuted {
      manager.onAudioCaptured = { [weak self] opusData in
        guard let self else { return }
        Task {
          try? await self.voiceConnection?.sendAudio(opusData)
        }
      }
      try? manager.startCapture()
    }
  }
}

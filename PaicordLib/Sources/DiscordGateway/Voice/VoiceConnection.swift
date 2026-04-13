import DiscordModels
import Foundation
import Logging
import NIO

/// Coordinates the full voice connection lifecycle:
/// Main Gateway -> Voice Gateway -> UDP -> IP Discovery -> Select Protocol -> Session -> Audio
public actor VoiceConnection {

  public enum State: Sendable, Equatable {
    case disconnected
    case connecting
    case waitingForServer
    case connectingVoiceGateway
    case performingIPDiscovery
    case selectingProtocol
    case connected
    case failed(String)

    public static func == (lhs: State, rhs: State) -> Bool {
      switch (lhs, rhs) {
      case (.disconnected, .disconnected),
        (.connecting, .connecting),
        (.waitingForServer, .waitingForServer),
        (.connectingVoiceGateway, .connectingVoiceGateway),
        (.performingIPDiscovery, .performingIPDiscovery),
        (.selectingProtocol, .selectingProtocol),
        (.connected, .connected):
        return true
      case (.failed(let a), .failed(let b)):
        return a == b
      default:
        return false
      }
    }
  }

  private let logger = Logger(label: "VoiceConnection")
  private let eventLoopGroup: any EventLoopGroup

  public private(set) var state: State = .disconnected
  public let stateCallback: @Sendable (State) -> Void

  private var voiceGateway: VoiceGatewayManager?
  private var udpConnection: VoiceUDPConnection?
  private var encryptor: VoiceEncryptor?
  private var eventTask: Task<Void, Never>?

  // Connection info from main gateway
  private var voiceToken: String?
  private var voiceEndpoint: String?
  private var voiceSessionId: String?
  private var userId: String?
  private var guildId: GuildSnowflake?
  private var channelId: ChannelSnowflake?

  // Voice state
  public private(set) var ssrc: UInt32?
  public private(set) var isSpeaking = false
  public private(set) var isMuted = false
  public private(set) var isDeafened = false

  public init(
    eventLoopGroup: any EventLoopGroup,
    stateCallback: @escaping @Sendable (State) -> Void
  ) {
    self.eventLoopGroup = eventLoopGroup
    self.stateCallback = stateCallback
  }

  // MARK: - Public API

  /// Called when the main gateway provides voice server update data.
  /// This kicks off the voice connection flow.
  public func handleVoiceServerUpdate(
    token: String,
    endpoint: String?,
    guildId: GuildSnowflake?,
    channelId: ChannelSnowflake,
    sessionId: String,
    userId: String
  ) async {
    guard let endpoint else {
      logger.error("Voice endpoint is nil")
      setState(.failed("No voice endpoint"))
      return
    }

    self.voiceToken = token
    self.voiceEndpoint = endpoint
    self.voiceSessionId = sessionId
    self.userId = userId
    self.guildId = guildId
    self.channelId = channelId

    await connectToVoiceGateway()
  }

  /// Disconnects from voice completely.
  public func disconnect() async {
    eventTask?.cancel()
    eventTask = nil
    await voiceGateway?.disconnect()
    await udpConnection?.close()
    voiceGateway = nil
    udpConnection = nil
    encryptor = nil
    setState(.disconnected)
  }

  /// Sends an Opus-encoded audio frame.
  public func sendAudio(_ opusData: Data) async throws {
    guard let udp = udpConnection, let enc = encryptor else {
      throw VoiceConnectionError.notConnected
    }
    try await udp.sendAudioPacket(opusData: opusData, encryptor: enc)
  }

  /// Tells Discord we are/aren't speaking.
  public func setSpeaking(_ speaking: Bool) async {
    guard let gw = voiceGateway, let ssrc else { return }
    self.isSpeaking = speaking
    await gw.sendSpeaking(speaking: speaking, ssrc: ssrc)
  }

  public func setMuted(_ muted: Bool) {
    self.isMuted = muted
  }

  public func setDeafened(_ deafened: Bool) {
    self.isDeafened = deafened
  }

  // MARK: - Connection Flow

  private func connectToVoiceGateway() async {
    guard let endpoint = voiceEndpoint,
      let token = voiceToken,
      let sessionId = voiceSessionId,
      let userId = userId
    else {
      setState(.failed("Missing connection info"))
      return
    }

    setState(.connectingVoiceGateway)

    let cleanEndpoint = endpoint.replacingOccurrences(of: ":443", with: "")
    let serverId = guildId?.rawValue ?? channelId?.rawValue ?? ""

    let gateway = VoiceGatewayManager(
      endpoint: cleanEndpoint,
      serverId: serverId,
      userId: userId,
      sessionId: sessionId,
      token: token,
      guildId: guildId,
      eventLoopGroup: eventLoopGroup
    )

    self.voiceGateway = gateway

    eventTask = Task { [weak self] in
      for await event in await gateway.events {
        guard let self else { return }
        await self.handleVoiceGatewayEvent(event)
      }
    }

    do {
      try await gateway.connect()
    } catch {
      logger.error("Voice gateway connection failed: \(error)")
      setState(.failed("Gateway connection failed"))
    }
  }

  private func handleVoiceGatewayEvent(_ event: VoiceGatewayManager.VoiceGatewayEvent) async {
    switch event {
    case .ready(let ready):
      self.ssrc = ready.ssrc
      setState(.performingIPDiscovery)
      await performIPDiscoveryAndSelect(ready: ready)

    case .sessionDescription(let desc):
      self.encryptor = VoiceEncryptor(secretKey: desc.secret_key)
      logger.info("Voice connection established with mode: \(desc.mode)")
      setState(.connected)

    case .disconnected:
      if state != .disconnected {
        setState(.disconnected)
      }

    case .heartbeatAck, .speaking, .resumed, .hello:
      break
    }
  }

  private func performIPDiscoveryAndSelect(ready: VoiceGatewayManager.VoiceReady) async {
    do {
      let udp = VoiceUDPConnection(
        serverIP: ready.ip,
        serverPort: ready.port,
        ssrc: ready.ssrc,
        eventLoopGroup: eventLoopGroup
      )
      self.udpConnection = udp

      try await udp.connect()
      let (discoveredIP, discoveredPort) = try await udp.performIPDiscovery()

      let preferredMode = selectEncryptionMode(from: ready.modes)
      logger.info("Selected encryption mode: \(preferredMode)")

      setState(.selectingProtocol)
      await voiceGateway?.sendSelectProtocol(
        address: discoveredIP,
        port: discoveredPort,
        mode: preferredMode
      )
    } catch {
      logger.error("IP discovery failed: \(error)")
      setState(.failed("IP Discovery failed: \(error.localizedDescription)"))
    }
  }

  private func selectEncryptionMode(from modes: [String]) -> String {
    let preferred = [
      "aead_aes256_gcm_rtpsize",
      "aead_aes256_gcm",
      "aead_xchacha20_poly1305_rtpsize",
      "xsalsa20_poly1305_lite_rtpsize"
    ]
    for mode in preferred {
      if modes.contains(mode) {
        return mode
      }
    }
    return modes.first ?? "aead_aes256_gcm_rtpsize"
  }

  private func setState(_ newState: State) {
    self.state = newState
    stateCallback(newState)
  }
}

public enum VoiceConnectionError: Error, LocalizedError {
  case notConnected
  case alreadyConnected
  case noAudioSession

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Not connected to voice"
    case .alreadyConnected: return "Already in a voice channel"
    case .noAudioSession: return "Audio session not available"
    }
  }
}

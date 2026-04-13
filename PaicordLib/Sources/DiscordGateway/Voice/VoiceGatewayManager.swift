import Atomics
import DiscordHTTP
import DiscordModels
import Foundation
import Logging
import NIO
import WSClient

import enum NIOWebSocket.WebSocketErrorCode
import struct NIOWebSocket.WebSocketOpcode

public actor VoiceGatewayManager {

  // MARK: - Voice Opcodes

  public enum VoiceOpcode: UInt8, Sendable, Codable {
    case identify = 0
    case selectProtocol = 1
    case ready = 2
    case heartbeat = 3
    case sessionDescription = 4
    case speaking = 5
    case heartbeatAck = 6
    case resume = 7
    case hello = 8
    case resumed = 9
    case clientPlatform = 20
    case daveProtocolPrepareTransition = 21
    case daveProtocolExecuteTransition = 22
    case daveProtocolTransitionReady = 23
    case daveProtocolPrepareEpoch = 24
  }

  // MARK: - Voice Gateway Payloads

  public struct VoiceIdentify: Sendable, Codable {
    public var server_id: String
    public var user_id: String
    public var session_id: String
    public var token: String
    public var max_dave_protocol_version: Int?
    public var video: Bool?

    public init(
      server_id: String,
      user_id: String,
      session_id: String,
      token: String,
      max_dave_protocol_version: Int? = nil,
      video: Bool? = false
    ) {
      self.server_id = server_id
      self.user_id = user_id
      self.session_id = session_id
      self.token = token
      self.max_dave_protocol_version = max_dave_protocol_version
      self.video = video
    }
  }

  public struct VoiceReady: Sendable, Codable {
    public var ssrc: UInt32
    public var ip: String
    public var port: UInt16
    public var modes: [String]
    public var heartbeat_interval: Double?
  }

  public struct VoiceSelectProtocol: Sendable, Codable {
    public var `protocol`: String
    public var data: ProtocolData

    public struct ProtocolData: Sendable, Codable {
      public var address: String
      public var port: UInt16
      public var mode: String
    }
  }

  public struct VoiceSessionDescription: Sendable, Codable {
    public var mode: String
    public var secret_key: [UInt8]
  }

  public struct VoiceSpeaking: Sendable, Codable {
    public var speaking: Int
    public var delay: Int
    public var ssrc: UInt32

    public init(speaking: Int, delay: Int = 0, ssrc: UInt32) {
      self.speaking = speaking
      self.delay = delay
      self.ssrc = ssrc
    }
  }

  public struct VoiceHello: Sendable, Codable {
    public var heartbeat_interval: Double
  }

  public struct VoiceResume: Sendable, Codable {
    public var server_id: String
    public var session_id: String
    public var token: String
    public var seq_ack: Int?
  }

  // MARK: - Voice Event

  public struct VoiceEvent: Sendable, Codable {
    public var op: UInt8
    public var d: AnyCodable?
    public var s: Int?

    public init(op: UInt8, d: AnyCodable? = nil) {
      self.op = op
      self.d = d
    }

    public init<T: Encodable>(op: UInt8, data: T) throws {
      self.op = op
      let encoded = try JSONEncoder().encode(data)
      self.d = try JSONDecoder().decode(AnyCodable.self, from: encoded)
    }
  }

  public enum AnyCodableValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dict([String: AnyCodable])
    case array([AnyCodable])
    case null
  }

  public struct AnyCodable: Sendable, Codable {
    public let storage: AnyCodableValue

    public init(_ value: some Sendable) {
      if let s = value as? String { storage = .string(s) }
      else if let i = value as? Int { storage = .int(i) }
      else if let d = value as? Double { storage = .double(d) }
      else if let b = value as? Bool { storage = .bool(b) }
      else { storage = .null }
    }

    public init(_ dict: [String: AnyCodable]) {
      storage = .dict(dict)
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let dict = try? container.decode([String: AnyCodable].self) {
        storage = .dict(dict)
      } else if let arr = try? container.decode([AnyCodable].self) {
        storage = .array(arr)
      } else if let str = try? container.decode(String.self) {
        storage = .string(str)
      } else if let int = try? container.decode(Int.self) {
        storage = .int(int)
      } else if let double = try? container.decode(Double.self) {
        storage = .double(double)
      } else if let bool = try? container.decode(Bool.self) {
        storage = .bool(bool)
      } else if container.decodeNil() {
        storage = .null
      } else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Cannot decode AnyCodable"
        )
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch storage {
      case .dict(let dict):
        try container.encode(dict)
      case .array(let arr):
        try container.encode(arr)
      case .string(let str):
        try container.encode(str)
      case .int(let int):
        try container.encode(int)
      case .double(let double):
        try container.encode(double)
      case .bool(let bool):
        try container.encode(bool)
      case .null:
        try container.encodeNil()
      }
    }
  }

  // MARK: - Properties

  private let logger: Logger
  private var outboundWriter: WebSocketOutboundWriter?
  private let eventLoopGroup: any EventLoopGroup

  private let endpoint: String
  private let serverId: String
  private let userId: String
  private let sessionId: String
  private let token: String
  private let guildId: GuildSnowflake?

  private var heartbeatTask: Task<Void, Never>?
  private var sequenceNumber: Int?
  private var lastNonceAck: Int?

  // MARK: - Public state

  public private(set) var ssrc: UInt32?
  public private(set) var udpIP: String?
  public private(set) var udpPort: UInt16?
  public private(set) var modes: [String]?
  public private(set) var secretKey: [UInt8]?
  public private(set) var encryptionMode: String?

  // MARK: - Event stream

  public enum VoiceGatewayEvent: Sendable {
    case ready(VoiceReady)
    case sessionDescription(VoiceSessionDescription)
    case speaking(VoiceSpeaking)
    case heartbeatAck
    case resumed
    case hello(VoiceHello)
    case disconnected
  }

  private var eventContinuations = [AsyncStream<VoiceGatewayEvent>.Continuation]()

  public var events: AsyncStream<VoiceGatewayEvent> {
    AsyncStream { continuation in
      self.eventContinuations.append(continuation)
    }
  }

  // MARK: - Init

  public init(
    endpoint: String,
    serverId: String,
    userId: String,
    sessionId: String,
    token: String,
    guildId: GuildSnowflake?,
    eventLoopGroup: any EventLoopGroup
  ) {
    self.endpoint = endpoint
    self.serverId = serverId
    self.userId = userId
    self.sessionId = sessionId
    self.token = token
    self.guildId = guildId
    self.eventLoopGroup = eventLoopGroup

    var logger = Logger(label: "VoiceGateway")
    logger[metadataKey: "server-id"] = .string(serverId)
    self.logger = logger
  }

  // MARK: - Connection

  public func connect() async throws {
    let wsURL = "wss://\(endpoint)/?v=8"
    logger.info("Connecting to voice gateway: \(wsURL)")

    let configuration = WebSocketClientConfiguration(
      maxFrameSize: 1 << 24,
      additionalHeaders: [
        .userAgent: "DiscordBot (Paicord, 1.0)",
        .origin: "https://discord.com"
      ]
    )

    Task {
      do {
        let closeFrame = try await WebSocketClient.connect(
          url: wsURL,
          configuration: configuration,
          eventLoopGroup: self.eventLoopGroup,
          logger: self.logger
        ) { inbound, outbound, context in
          await self.setupOutboundWriter(outbound)
          self.logger.debug("Voice WebSocket connected")

          for try await message in inbound.messages(maxSize: 1 << 24) {
            await self.processMessage(message)
          }
        }

        logger.debug(
          "Voice WebSocket closed",
          metadata: [
            "closeCode": .string(String(describing: closeFrame?.closeCode))
          ]
        )
        await self.handleDisconnect()
      } catch {
        logger.error(
          "Voice WebSocket error: \(error)"
        )
        await self.handleDisconnect()
      }
    }
  }

  public func disconnect() async {
    heartbeatTask?.cancel()
    heartbeatTask = nil
    do {
      try await outboundWriter?.close(.goingAway, reason: nil)
    } catch {
      logger.warning("Voice WS close error: \(error)")
    }
    outboundWriter = nil
    for continuation in eventContinuations {
      continuation.yield(.disconnected)
      continuation.finish()
    }
    eventContinuations.removeAll()
  }

  // MARK: - Send

  public func sendSelectProtocol(address: String, port: UInt16, mode: String) async {
    let payload = VoiceSelectProtocol(
      protocol: "udp",
      data: .init(address: address, port: port, mode: mode)
    )
    do {
      let event = try VoiceEvent(op: VoiceOpcode.selectProtocol.rawValue, data: payload)
      try await send(event)
    } catch {
      logger.error("Failed to send select protocol: \(error)")
    }
  }

  public func sendSpeaking(speaking: Bool, ssrc: UInt32) async {
    let payload = VoiceSpeaking(
      speaking: speaking ? 1 : 0,
      ssrc: ssrc
    )
    do {
      let event = try VoiceEvent(op: VoiceOpcode.speaking.rawValue, data: payload)
      try await send(event)
    } catch {
      logger.error("Failed to send speaking: \(error)")
    }
  }

  // MARK: - Internal

  private func setupOutboundWriter(_ writer: WebSocketOutboundWriter) {
    self.outboundWriter = writer
  }

  private func processMessage(_ message: WebSocketMessage) {
    let buffer: ByteBuffer
    switch message {
    case .text(let string):
      buffer = ByteBuffer(string: string)
    case .binary(let buf):
      buffer = buf
    }

    do {
      let event = try JSONDecoder().decode(VoiceEvent.self, from: Data(buffer: buffer, byteTransferStrategy: .noCopy))
      Task { await handleEvent(event) }
    } catch {
      logger.debug("Failed to decode voice event: \(error)")
    }
  }

  private func handleEvent(_ event: VoiceEvent) async {
    guard let opcode = VoiceOpcode(rawValue: event.op) else {
      logger.debug("Unknown voice opcode: \(event.op)")
      return
    }

    switch opcode {
    case .hello:
      if let data = decodePayload(VoiceHello.self, from: event) {
        logger.debug("Voice Hello, heartbeat interval: \(data.heartbeat_interval)")
        startHeartbeat(interval: data.heartbeat_interval)
        await sendIdentify()
        for c in eventContinuations { c.yield(.hello(data)) }
      }

    case .ready:
      if let data = decodePayload(VoiceReady.self, from: event) {
        logger.info("Voice Ready: ssrc=\(data.ssrc), ip=\(data.ip), port=\(data.port)")
        self.ssrc = data.ssrc
        self.udpIP = data.ip
        self.udpPort = data.port
        self.modes = data.modes
        for c in eventContinuations { c.yield(.ready(data)) }
      }

    case .sessionDescription:
      if let data = decodePayload(VoiceSessionDescription.self, from: event) {
        logger.info("Voice Session Description: mode=\(data.mode)")
        self.secretKey = data.secret_key
        self.encryptionMode = data.mode
        for c in eventContinuations { c.yield(.sessionDescription(data)) }
      }

    case .heartbeatAck:
      logger.trace("Voice heartbeat ACK")
      for c in eventContinuations { c.yield(.heartbeatAck) }

    case .speaking:
      if let data = decodePayload(VoiceSpeaking.self, from: event) {
        for c in eventContinuations { c.yield(.speaking(data)) }
      }

    case .resumed:
      logger.info("Voice resumed")
      for c in eventContinuations { c.yield(.resumed) }

    case .daveProtocolPrepareTransition:
      logger.debug("DAVE prepare transition received (not yet supported)")
      await sendDaveTransitionReady()

    case .daveProtocolExecuteTransition:
      logger.debug("DAVE execute transition received")

    case .daveProtocolPrepareEpoch:
      logger.debug("DAVE prepare epoch received")

    default:
      logger.debug("Unhandled voice opcode: \(event.op)")
    }
  }

  private func sendIdentify() async {
    let identify = VoiceIdentify(
      server_id: serverId,
      user_id: userId,
      session_id: sessionId,
      token: token,
      max_dave_protocol_version: 0,
      video: false
    )
    do {
      let event = try VoiceEvent(op: VoiceOpcode.identify.rawValue, data: identify)
      try await send(event)
      logger.debug("Sent voice identify")
    } catch {
      logger.error("Failed to send voice identify: \(error)")
    }
  }

  private func sendDaveTransitionReady() async {
    let event = VoiceEvent(op: VoiceOpcode.daveProtocolTransitionReady.rawValue, d: .init(["transition_id": AnyCodable(0)]))
    do {
      try await send(event)
    } catch {
      logger.error("Failed to send DAVE transition ready: \(error)")
    }
  }

  private func startHeartbeat(interval: Double) {
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(Int64(interval)))
        guard !Task.isCancelled else { return }
        await self?.sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async {
    let nonce = Int(Date().timeIntervalSince1970 * 1000)
    let event = VoiceEvent(op: VoiceOpcode.heartbeat.rawValue, d: AnyCodable(nonce))
    do {
      try await send(event)
    } catch {
      logger.debug("Failed to send voice heartbeat: \(error)")
    }
  }

  private func send(_ event: VoiceEvent) async throws {
    guard let writer = outboundWriter else {
      logger.warning("No voice WS writer available")
      return
    }
    let data = try JSONEncoder().encode(event)
    try await writer.write(
      .custom(
        .init(
          fin: true,
          opcode: .text,
          data: ByteBuffer(data: data)
        )
      )
    )
  }

  private func handleDisconnect() {
    heartbeatTask?.cancel()
    heartbeatTask = nil
    for c in eventContinuations { c.yield(.disconnected) }
  }

  private nonisolated func decodePayload<T: Decodable>(_ type: T.Type, from event: VoiceEvent) -> T? {
    guard let d = event.d else { return nil }
    do {
      let data = try JSONEncoder().encode(d)
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      return nil
    }
  }
}

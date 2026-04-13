import Foundation
import Logging
import NIO

public actor VoiceUDPConnection {

  private let logger: Logger
  private let eventLoopGroup: any EventLoopGroup
  private var bootstrap: DatagramBootstrap?
  private var udpChannel: (any NIOCore.Channel)?

  private let serverIP: String
  private let serverPort: UInt16
  private let ssrc: UInt32

  public private(set) var discoveredIP: String?
  public private(set) var discoveredPort: UInt16?

  private var sequenceNumber: UInt16 = 0
  private var timestamp: UInt32 = 0

  private var receiveContinuations = [AsyncStream<RTPPacket>.Continuation]()

  public var receivedPackets: AsyncStream<RTPPacket> {
    AsyncStream { continuation in
      self.receiveContinuations.append(continuation)
    }
  }

  public struct RTPPacket: Sendable {
    public let ssrc: UInt32
    public let sequenceNumber: UInt16
    public let timestamp: UInt32
    public let payload: Data
  }

  public init(
    serverIP: String,
    serverPort: UInt16,
    ssrc: UInt32,
    eventLoopGroup: any EventLoopGroup
  ) {
    self.serverIP = serverIP
    self.serverPort = serverPort
    self.ssrc = ssrc
    self.eventLoopGroup = eventLoopGroup
    self.logger = Logger(label: "VoiceUDP")
  }

  // MARK: - Connection & IP Discovery

  public func connect() async throws {
    let handler = UDPHandler(connection: self)
    let bootstrap = DatagramBootstrap(group: eventLoopGroup)
      .channelOption(.socketOption(.so_reuseaddr), value: 1)
      .channelInitializer { channel in
        channel.pipeline.addHandler(handler)
      }

    self.bootstrap = bootstrap
    let channel = try await bootstrap.bind(host: "0.0.0.0", port: 0).get()
    self.udpChannel = channel
    logger.info("UDP channel bound on port \(channel.localAddress?.port ?? 0)")
  }

  /// Performs IP discovery per Discord's protocol.
  /// Sends a 74-byte packet with our SSRC, receives back our external IP/port.
  public func performIPDiscovery() async throws -> (ip: String, port: UInt16) {
    guard let channel = udpChannel else {
      throw VoiceUDPError.notConnected
    }

    var discoveryPacket = ByteBuffer()
    discoveryPacket.writeInteger(UInt16(0x1))  // type: request
    discoveryPacket.writeInteger(UInt16(70))   // length
    discoveryPacket.writeInteger(ssrc)

    let padding = [UInt8](repeating: 0, count: 66)
    discoveryPacket.writeBytes(padding)

    let remoteAddress = try SocketAddress(ipAddress: serverIP, port: Int(serverPort))
    let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: discoveryPacket)
    try await channel.writeAndFlush(envelope)
    logger.debug("Sent IP discovery packet")

    let (ip, port) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, UInt16), any Error>) in
      Task {
        await self.setIPDiscoveryContinuation(continuation)
      }
    }

    self.discoveredIP = ip
    self.discoveredPort = port
    logger.info("IP Discovery result: \(ip):\(port)")
    return (ip, port)
  }

  private var ipDiscoveryContinuation: CheckedContinuation<(String, UInt16), any Error>?

  func setIPDiscoveryContinuation(_ continuation: CheckedContinuation<(String, UInt16), any Error>) {
    self.ipDiscoveryContinuation = continuation
  }

  func handleIPDiscoveryResponse(_ buffer: ByteBuffer) {
    var buf = buffer
    guard buf.readableBytes >= 74 else {
      ipDiscoveryContinuation?.resume(throwing: VoiceUDPError.invalidDiscoveryResponse)
      ipDiscoveryContinuation = nil
      return
    }

    _ = buf.readInteger(as: UInt16.self) // type
    _ = buf.readInteger(as: UInt16.self) // length
    _ = buf.readInteger(as: UInt32.self) // ssrc

    guard let ipBytes = buf.readBytes(length: 64) else {
      ipDiscoveryContinuation?.resume(throwing: VoiceUDPError.invalidDiscoveryResponse)
      ipDiscoveryContinuation = nil
      return
    }

    let ip = String(bytes: ipBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
    let port = buf.readInteger(as: UInt16.self) ?? 0

    ipDiscoveryContinuation?.resume(returning: (ip, port))
    ipDiscoveryContinuation = nil
  }

  // MARK: - Audio Sending

  /// Sends an encrypted Opus audio frame over RTP.
  public func sendAudioPacket(
    opusData: Data,
    encryptor: VoiceEncryptor
  ) async throws {
    guard let channel = udpChannel else {
      throw VoiceUDPError.notConnected
    }

    sequenceNumber &+= 1
    timestamp &+= 960  // 20ms of 48kHz audio

    var rtpHeader = ByteBuffer()
    rtpHeader.writeInteger(UInt8(0x80))        // version 2
    rtpHeader.writeInteger(UInt8(0x78))        // payload type 120 (Opus)
    rtpHeader.writeInteger(sequenceNumber)
    rtpHeader.writeInteger(timestamp)
    rtpHeader.writeInteger(ssrc)

    let headerBytes = Data(rtpHeader.readableBytesView)

    let encrypted = try encryptor.encrypt(
      header: headerBytes,
      audio: opusData,
      nonce: sequenceNumber,
      ssrc: ssrc
    )

    var packet = ByteBuffer()
    packet.writeBytes(headerBytes)
    packet.writeBytes(encrypted)

    let remoteAddress = try SocketAddress(ipAddress: serverIP, port: Int(serverPort))
    let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: packet)
    try await channel.writeAndFlush(envelope)
  }

  /// Sends 5 silence frames (required by Discord when stopping speaking).
  public func sendSilenceFrames(encryptor: VoiceEncryptor) async throws {
    let silenceFrame = Data([0xF8, 0xFF, 0xFE])
    for _ in 0..<5 {
      try await sendAudioPacket(opusData: silenceFrame, encryptor: encryptor)
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  public func close() async {
    try? await udpChannel?.close()
    udpChannel = nil
    for c in receiveContinuations {
      c.finish()
    }
    receiveContinuations.removeAll()
  }

  func handleIncomingPacket(_ buffer: ByteBuffer) {
    if ipDiscoveryContinuation != nil {
      handleIPDiscoveryResponse(buffer)
      return
    }

    var buf = buffer
    guard buf.readableBytes >= 12 else { return }

    _ = buf.readInteger(as: UInt8.self)  // version/padding
    _ = buf.readInteger(as: UInt8.self)  // payload type
    let seq = buf.readInteger(as: UInt16.self) ?? 0
    let ts = buf.readInteger(as: UInt32.self) ?? 0
    let ssrc = buf.readInteger(as: UInt32.self) ?? 0
    let remaining = Data(buf.readableBytesView)

    let packet = RTPPacket(
      ssrc: ssrc,
      sequenceNumber: seq,
      timestamp: ts,
      payload: remaining
    )

    for c in receiveContinuations {
      c.yield(packet)
    }
  }

  // MARK: - UDP Channel Handler

  private final class UDPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    let connection: VoiceUDPConnection

    init(connection: VoiceUDPConnection) {
      self.connection = connection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let envelope = unwrapInboundIn(data)
      Task { await connection.handleIncomingPacket(envelope.data) }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
      Task { await connection.close() }
    }
  }
}

public enum VoiceUDPError: Error, LocalizedError {
  case notConnected
  case invalidDiscoveryResponse
  case encryptionFailed

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "UDP connection not established"
    case .invalidDiscoveryResponse: return "Invalid IP discovery response"
    case .encryptionFailed: return "Voice encryption failed"
    }
  }
}

//
//  AudioManager.swift
//  Paicord
//
//  Voice audio capture and playback using AVAudioEngine + AudioToolbox Opus.
//

import AVFoundation
import AudioToolbox
import Foundation

@Observable
final class AudioManager: @unchecked Sendable {

  private var engine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?
  private var playerNode: AVAudioPlayerNode?

  private(set) var isCapturing = false
  private(set) var isPlaying = false

  private var opusEncoder: AudioConverter?
  private var opusDecoder: AudioConverter?

  var onAudioCaptured: (@Sendable (Data) -> Void)?

  // Discord requires 48kHz stereo Opus
  static let sampleRate: Double = 48000
  static let channels: UInt32 = 2
  static let frameSize: UInt32 = 960  // 20ms at 48kHz

  // MARK: - Microphone Capture

  /// Prompt for microphone access. Returns true once the user has granted it.
  static func requestMicrophoneAccess() async -> Bool {
    #if os(iOS)
      if #available(iOS 17.0, *) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
          return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
      } else {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
          return await withCheckedContinuation { cont in
            session.requestRecordPermission { cont.resume(returning: $0) }
          }
        @unknown default: return false
        }
      }
    #else
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized: return true
      case .denied, .restricted: return false
      case .notDetermined:
        return await AVCaptureDevice.requestAccess(for: .audio)
      @unknown default: return false
      }
    #endif
  }

  func startCapture() throws {
    guard !isCapturing else { return }

    let engine = AVAudioEngine()
    self.engine = engine

    let inputNode = engine.inputNode
    self.inputNode = inputNode

    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      let mode: AVAudioSession.Mode =
        ProcessInfo.processInfo.isMacCatalystApp ? .default : .voiceChat
      try session.setCategory(
        .playAndRecord,
        mode: mode,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try session.setActive(true)
    #endif

    // Voice processing (AEC) pulls in audioanalyticsd, which is blocked by
    // the Mac Catalyst sandbox. Disable it explicitly so startCapture doesn't
    // crash with a mach-lookup precondition failure on macOS.
    try? inputNode.setVoiceProcessingEnabled(false)

    let inputFormat = inputNode.outputFormat(forBus: 0)

    let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate,
      channels: AVAudioChannelCount(Self.channels),
      interleaved: false
    )!

    let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

    setupOpusEncoder()

    inputNode.installTap(onBus: 0, bufferSize: Self.frameSize, format: inputFormat) {
      [weak self] buffer, _ in
      guard let self, let converter else { return }

      let convertedBuffer = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: Self.frameSize
      )!

      var error: NSError?
      let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }

      guard status != .error, error == nil else { return }

      if let opusData = self.encodeOpus(from: convertedBuffer) {
        self.onAudioCaptured?(opusData)
      }
    }

    try engine.start()
    isCapturing = true
  }

  func stopCapture() {
    inputNode?.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    inputNode = nil
    isCapturing = false

    destroyOpusEncoder()

    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  // MARK: - Audio Playback

  func startPlayback() throws {
    guard !isPlaying else { return }

    if engine == nil {
      engine = AVAudioEngine()
    }

    let player = AVAudioPlayerNode()
    self.playerNode = player
    engine?.attach(player)

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate,
      channels: AVAudioChannelCount(Self.channels),
      interleaved: false
    )!

    engine?.connect(player, to: engine!.mainMixerNode, format: format)

    if !engine!.isRunning {
      try engine?.start()
    }

    player.play()
    isPlaying = true
    setupOpusDecoder()
  }

  func stopPlayback() {
    playerNode?.stop()
    if let player = playerNode {
      engine?.detach(player)
    }
    playerNode = nil
    isPlaying = false
    destroyOpusDecoder()
  }

  /// Decodes and plays an incoming Opus audio frame.
  func playOpusFrame(_ opusData: Data) {
    guard let playerNode, isPlaying else { return }

    guard let pcmBuffer = decodeOpus(from: opusData) else { return }
    playerNode.scheduleBuffer(pcmBuffer)
  }

  // MARK: - Opus Encoding (AudioToolbox)

  private func setupOpusEncoder() {
    var inputDesc = AudioStreamBasicDescription(
      mSampleRate: Self.sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
      mBytesPerPacket: 4,
      mFramesPerPacket: 1,
      mBytesPerFrame: 4,
      mChannelsPerFrame: Self.channels,
      mBitsPerChannel: 32,
      mReserved: 0
    )

    var outputDesc = AudioStreamBasicDescription(
      mSampleRate: Self.sampleRate,
      mFormatID: kAudioFormatOpus,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: Self.frameSize,
      mBytesPerFrame: 0,
      mChannelsPerFrame: Self.channels,
      mBitsPerChannel: 0,
      mReserved: 0
    )

    var converter: AudioConverterRef?
    let status = AudioConverterNew(&inputDesc, &outputDesc, &converter)
    if status == noErr, let converter {
      self.opusEncoder = .init(ref: converter)

      var bitrate: UInt32 = 64000
      AudioConverterSetProperty(
        converter,
        kAudioConverterEncodeBitRate,
        UInt32(MemoryLayout<UInt32>.size),
        &bitrate
      )
    }
  }

  private func destroyOpusEncoder() {
    if let encoder = opusEncoder {
      AudioConverterDispose(encoder.ref)
      opusEncoder = nil
    }
  }

  private func encodeOpus(from buffer: AVAudioPCMBuffer) -> Data? {
    guard let encoder = opusEncoder else { return nil }

    let frameCount = buffer.frameLength
    guard frameCount > 0 else { return nil }

    var outputBuffer = Data(count: 4000)
    var outputPacketDesc = AudioStreamPacketDescription()
    var ioOutputDataPacketSize: UInt32 = 1

    var fillBuf = AudioBuffer(
      mNumberChannels: Self.channels,
      mDataByteSize: buffer.frameLength * 4,
      mData: buffer.floatChannelData?[0]
    )
    var fillBufList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: fillBuf
    )

    let status = outputBuffer.withUnsafeMutableBytes { outputPtr in
      var outBuf = AudioBuffer(
        mNumberChannels: Self.channels,
        mDataByteSize: 4000,
        mData: outputPtr.baseAddress
      )
      var outBufList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: outBuf
      )

      return AudioConverterFillComplexBuffer(
        encoder.ref,
        { (
          _,
          ioNumberDataPackets,
          ioData,
          outDataPacketDescription,
          inUserData
        ) -> OSStatus in
          let bufListPtr = inUserData!.assumingMemoryBound(to: AudioBufferList.self)
          ioData.pointee.mBuffers = bufListPtr.pointee.mBuffers
          ioNumberDataPackets.pointee = 1
          return noErr
        },
        &fillBufList,
        &ioOutputDataPacketSize,
        &outBufList,
        &outputPacketDesc
      )
    }

    guard status == noErr else { return nil }

    let packetSize = Int(outputPacketDesc.mDataByteSize)
    guard packetSize > 0 else { return nil }
    return outputBuffer.prefix(packetSize)
  }

  // MARK: - Opus Decoding (AudioToolbox)

  private func setupOpusDecoder() {
    var inputDesc = AudioStreamBasicDescription(
      mSampleRate: Self.sampleRate,
      mFormatID: kAudioFormatOpus,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: Self.frameSize,
      mBytesPerFrame: 0,
      mChannelsPerFrame: Self.channels,
      mBitsPerChannel: 0,
      mReserved: 0
    )

    var outputDesc = AudioStreamBasicDescription(
      mSampleRate: Self.sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
      mBytesPerPacket: 4,
      mFramesPerPacket: 1,
      mBytesPerFrame: 4,
      mChannelsPerFrame: Self.channels,
      mBitsPerChannel: 32,
      mReserved: 0
    )

    var converter: AudioConverterRef?
    let status = AudioConverterNew(&inputDesc, &outputDesc, &converter)
    if status == noErr, let converter {
      self.opusDecoder = .init(ref: converter)
    }
  }

  private func destroyOpusDecoder() {
    if let decoder = opusDecoder {
      AudioConverterDispose(decoder.ref)
      opusDecoder = nil
    }
  }

  private func decodeOpus(from opusData: Data) -> AVAudioPCMBuffer? {
    guard let decoder = opusDecoder else { return nil }

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate,
      channels: AVAudioChannelCount(Self.channels),
      interleaved: false
    )!

    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.frameSize) else {
      return nil
    }

    var inputData = opusData
    var inputPacketDesc = AudioStreamPacketDescription(
      mStartOffset: 0,
      mVariableFramesInPacket: 0,
      mDataByteSize: UInt32(opusData.count)
    )
    var ioOutputDataPacketSize: UInt32 = Self.frameSize

    let status = inputData.withUnsafeMutableBytes { inputPtr in
      var inBuf = AudioBuffer(
        mNumberChannels: Self.channels,
        mDataByteSize: UInt32(opusData.count),
        mData: inputPtr.baseAddress
      )
      var inBufList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: inBuf
      )

      var outBuf = AudioBuffer(
        mNumberChannels: Self.channels,
        mDataByteSize: Self.frameSize * 4 * Self.channels,
        mData: pcmBuffer.floatChannelData?[0]
      )
      var outBufList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: outBuf
      )

      return AudioConverterFillComplexBuffer(
        decoder.ref,
        { (
          _,
          ioNumberDataPackets,
          ioData,
          outDataPacketDescription,
          inUserData
        ) -> OSStatus in
          let bufListPtr = inUserData!.assumingMemoryBound(to: AudioBufferList.self)
          ioData.pointee.mBuffers = bufListPtr.pointee.mBuffers
          ioNumberDataPackets.pointee = 1
          return noErr
        },
        &inBufList,
        &ioOutputDataPacketSize,
        &outBufList,
        nil
      )
    }

    guard status == noErr else { return nil }
    pcmBuffer.frameLength = Self.frameSize
    return pcmBuffer
  }

  // MARK: - Internal wrapper

  private struct AudioConverter: @unchecked Sendable {
    let ref: AudioConverterRef
  }

  deinit {
    stopCapture()
    stopPlayback()
  }
}

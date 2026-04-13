//
//  CallRingPlayer.swift
//  Paicord
//
//  Outgoing-call ringback tone. Generates the standard US PSTN ringback —
//  a sum of 440 Hz and 480 Hz sines at equal amplitude, gated 2 seconds on
//  then 4 seconds off, with short fade-in/out envelopes at the boundaries
//  so it doesn't click.
//

import AVFoundation
import Foundation

final class CallRingPlayer: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private var sourceNode: AVAudioSourceNode?
  private var isRunning = false

  private let sampleRate: Double = 48_000
  private let toneLow: Double = 440
  private let toneHigh: Double = 480
  private let ringOn: Double = 2.0
  private let ringOff: Double = 4.0
  private let fade: Double = 0.02
  private let amplitude: Float = 0.18

  func start() {
    guard !isRunning else { return }
    isRunning = true

    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers, .duckOthers]
      )
      try? session.setActive(true, options: [])
    #endif

    let format = AVAudioFormat(
      standardFormatWithSampleRate: sampleRate,
      channels: 1
    )!

    var phaseLow: Double = 0
    var phaseHigh: Double = 0
    var sampleClock: Double = 0

    let sampleRate = self.sampleRate
    let toneLow = self.toneLow
    let toneHigh = self.toneHigh
    let ringOn = self.ringOn
    let ringOff = self.ringOff
    let fade = self.fade
    let amplitude = self.amplitude

    let twoPi = 2.0 * Double.pi
    let incLow = twoPi * toneLow / sampleRate
    let incHigh = twoPi * toneHigh / sampleRate
    let period = ringOn + ringOff

    let node = AVAudioSourceNode(format: format) {
      _,
      _,
      frameCount,
      audioBufferList in
      let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
      for frame in 0..<Int(frameCount) {
        let t = sampleClock / sampleRate
        let phaseInCycle = t.truncatingRemainder(dividingBy: period)

        var env: Float = 0
        if phaseInCycle < ringOn {
          if phaseInCycle < fade {
            env = Float(phaseInCycle / fade)
          } else if phaseInCycle > ringOn - fade {
            env = Float((ringOn - phaseInCycle) / fade)
          } else {
            env = 1
          }
        }

        let sLow = Float(sin(phaseLow))
        let sHigh = Float(sin(phaseHigh))
        let sample = (sLow + sHigh) * 0.5 * amplitude * env

        phaseLow += incLow
        if phaseLow > twoPi { phaseLow -= twoPi }
        phaseHigh += incHigh
        if phaseHigh > twoPi { phaseHigh -= twoPi }
        sampleClock += 1

        for buffer in abl {
          let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
          ptr?[frame] = sample
        }
      }
      return noErr
    }

    sourceNode = node
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    do {
      try engine.start()
    } catch {
      isRunning = false
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    engine.stop()
    if let node = sourceNode {
      engine.detach(node)
    }
    sourceNode = nil
  }
}

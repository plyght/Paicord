//
//  MacSwipeSupport.swift
//  Paicord
//

#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  @Observable
  final class CellSwipeState {
    var offset: CGFloat = 0
    var tracking = false
    private var accumulated: CGFloat = 0
    private var hapticFired = false

    func handle(
      _ event: NSEvent,
      threshold: CGFloat,
      maxOffset: CGFloat,
      onCommit: () -> Void
    ) -> Bool {
      if !event.momentumPhase.isEmpty { return tracking }

      let dx = event.scrollingDeltaX
      let dy = event.scrollingDeltaY

      if !tracking {
        guard abs(dx) > abs(dy), dx > 0.5 else { return false }
        tracking = true
        accumulated = 0
        hapticFired = false
      }

      if event.phase == .ended || event.phase == .cancelled {
        let triggered = event.phase == .ended && offset >= threshold
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
          offset = 0
        }
        tracking = false
        accumulated = 0
        hapticFired = false
        if triggered { onCommit() }
        return true
      }

      accumulated += dx
      let damped = min(maxOffset, max(0, accumulated * 0.7))
      offset = damped
      if !hapticFired && damped >= threshold {
        hapticFired = true
        ImpactGenerator.impact(style: .medium)
      }
      return true
    }

    func resetIfIdle() {
      guard !tracking else { return }
      offset = 0
    }
  }

  @MainActor
  final class MacScrollMonitor {
    static let shared = MacScrollMonitor()
    var active: ((NSEvent) -> Bool)?

    private init() {
      NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        MainActor.assumeIsolated {
          if MacScrollMonitor.shared.active?(event) == true {
            return nil as NSEvent?
          }
          return event
        }
      }
    }
  }
#endif

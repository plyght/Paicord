//
//  QuickReactionPicker.swift
//  Paicord
//

import SwiftUI

struct QuickReactionPicker: View {
  static let defaults: [String] = ["👍", "❤️", "😂", "😮", "😢", "🔥"]

  var applied: Set<String> = []
  var onPick: (String) -> Void
  var onMore: (() -> Void)? = nil

  @State private var appeared = false

  private var emojis: [String] {
    let recent = RecentReactionsStore.shared.recent
    var seen = Set<String>()
    var out: [String] = []
    for e in recent + Self.defaults where seen.insert(e).inserted {
      out.append(e)
      if out.count == 6 { break }
    }
    return out
  }

  var body: some View {
    HStack(spacing: 1) {
      ForEach(Array(emojis.enumerated()), id: \.offset) { idx, emoji in
        ReactionButton(
          label: Text(emoji).font(.system(size: 20)),
          delay: Double(idx) * 0.025,
          appeared: appeared,
          selected: applied.contains(emoji)
        ) {
          ImpactGenerator.impact(style: .light)
          onPick(emoji)
        }
      }
      if let onMore {
        ReactionButton(
          label: Image(systemName: "plus")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary),
          delay: Double(emojis.count) * 0.025,
          appeared: appeared,
          selected: false,
          action: onMore
        )
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .glassEffect(.regular, in: .capsule)
    .onAppear { appeared = true }
  }

  private struct ReactionButton<Label: View>: View {
    let label: Label
    let delay: Double
    let appeared: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        label
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.accentColor.opacity(selected ? 0.28 : 0))
          )
          .overlay(
            Circle()
              .strokeBorder(
                Color.accentColor.opacity(selected ? 0.9 : 0),
                lineWidth: 1.5
              )
          )
          .contentShape(Circle())
          .scaleEffect(appeared ? 1 : 0.4)
          .opacity(appeared ? 1 : 0)
          .animation(
            .spring(response: 0.35, dampingFraction: 0.65).delay(delay),
            value: appeared
          )
          .animation(.easeOut(duration: 0.18), value: selected)
      }
      .buttonStyle(.plain)
    }
  }
}

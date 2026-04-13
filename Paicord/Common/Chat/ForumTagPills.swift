//
//  ForumTagPills.swift
//  Paicord
//

import PaicordLib
import SwiftUI

struct ForumTagPills: View {
  var availableTags: [DiscordChannel.ForumTag]
  var appliedTagIds: [ForumTagSnowflake]?

  private var visibleTags: [DiscordChannel.ForumTag] {
    if let appliedTagIds, !appliedTagIds.isEmpty {
      let appliedSet = Set(appliedTagIds)
      return availableTags.filter { appliedSet.contains($0.id) }
    }
    return availableTags
  }

  var body: some View {
    if !visibleTags.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(visibleTags, id: \.id) { tag in
            HStack(spacing: 3) {
              if let name = tag.emoji_name, !name.isEmpty {
                Text(name)
                  .font(.caption2)
              }
              Text(tag.name)
                .font(.caption2)
                .fontWeight(.medium)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              Color.secondary.opacity(0.2),
              in: Capsule()
            )
          }
        }
      }
    }
  }
}

//
//  UnreadBadge.swift
//  Paicord
//

import SwiftUI

struct UnreadBadge: View {
  var hasUnread: Bool
  var mentionCount: Int

  var body: some View {
    HStack(spacing: 4) {
      if mentionCount > 0 {
        Text(mentionCount > 99 ? "99+" : "\(mentionCount)")
          .font(.caption2)
          .fontWeight(.bold)
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(Color.red, in: Capsule())
      } else if hasUnread {
        Circle()
          .fill(.primary)
          .frame(width: 8, height: 8)
      }
    }
  }
}

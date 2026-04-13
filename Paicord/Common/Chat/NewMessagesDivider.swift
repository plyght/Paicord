//
//  NewMessagesDivider.swift
//  Paicord
//

import SwiftUI

struct NewMessagesDivider: View {
  var body: some View {
    HStack(spacing: 8) {
      Rectangle()
        .fill(Color.red)
        .frame(height: 1)
      Text("NEW")
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Color.red, in: Capsule())
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
  }
}

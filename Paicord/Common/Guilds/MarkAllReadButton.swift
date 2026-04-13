//
//  MarkAllReadButton.swift
//  Paicord
//

import PaicordLib
import SwiftUI

struct MarkAllReadButton: View {
  @Environment(\.gateway) var gw

  private var hasAnyUnread: Bool {
    gw.readStates.hasAnyUnread
  }

  var body: some View {
    Button {
      ImpactGenerator.impact(style: .light)
      gw.readStates.markAllRead()
    } label: {
      Text("Read All")
        .font(.system(size: MarkAllRead.fontSize, weight: .semibold))
        .foregroundStyle(
          hasAnyUnread
            ? MarkAllRead.activeForeground
            : MarkAllRead.inactiveForeground
        )
        .padding(.horizontal, MarkAllRead.horizontalPadding)
        .padding(.vertical, MarkAllRead.verticalPadding)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
    .buttonStyle(.borderless)
    .disabled(!hasAnyUnread)
    .help("Mark all servers as read")
    .padding(.vertical, MarkAllRead.outerVerticalPadding)
    .animation(.default, value: hasAnyUnread)
  }
}

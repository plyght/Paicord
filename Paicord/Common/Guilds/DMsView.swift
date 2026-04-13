//
//  DMsView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 06/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

//
//  DMsView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 22/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUIX

struct DMsView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme
  var body: some View {
    ScrollFadeMask {
      #if os(macOS)
        VStack(spacing: 0) {
          HStack(alignment: .center, spacing: Spacing.standard) {
            Text("Direct Messages")
              .font(.title3)
              .bold()
              .foregroundStyle(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.horizontal, Spacing.large)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: Sidebar.headerHeight)

          Divider()
        }
      #else
        if idiom == .phone {
          VStack(spacing: 0) {
            VStack(alignment: .leading) {
              Text("Direct Messages")
                .font(.title3)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Divider()
          }
        }
      #endif

      let channels = gw.user.privateChannels.values
      LazyVStack(spacing: Spacing.compact) {
        ForEach(channels) { channel in
          ChannelButton(channels: [:], channel: channel)
        }
      }
      .padding(.vertical, Spacing.compact)
    }
    .frame(maxWidth: .infinity)
    #if os(macOS)
    .background(.clear)
    #else
    .background(theme.common.secondaryBackground.opacity(0.5))
    #endif
  }
}

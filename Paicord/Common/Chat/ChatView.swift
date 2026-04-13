//
//  ChatView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import Collections
import PaicordLib
@_spi(Advanced) import SwiftUIIntrospect
import SwiftUIX

struct ChatView: View {
  @State var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme

  @State private var isNearBottom: Bool = true
  @State private var scrollProxy: ScrollViewProxy? = nil
  private static let bottomSentinelId: String = "__paicord_bottom_sentinel__"

  var drain: MessageDrainStore { gw.messageDrain }

  @AppStorage("Paicord.Appearance.ChatMessagesAnimated")
  var chatAnimatesMessages: Bool = false

  init(vm: ChannelStore) { self._vm = .init(initialValue: vm) }

  #if os(macOS)
    @FocusState private var isChatFocused: Bool
  #endif

  var body: some View {
    let orderedMessages = vm.messages.values
    let pendingMessages = drain.pendingMessages[vm.channelId, default: [:]]
    let currentUserID = gw.user.currentUser?.id
    let blocked: Set<UserSnowflake> = {
      var s = Set<UserSnowflake>()
      for (id, rel) in gw.user.relationships
      where rel.type == .blocked || rel.user_ignored {
        s.insert(id)
      }
      return s
    }()
    let userRoles: [RoleSnowflake]? = {
      guard let currentUserID else { return nil }
      return vm.guildStore?.members[currentUserID]?.roles
    }()

    let shouldAnimate =
      orderedMessages.last?.author?.id != currentUserID
    VStack(spacing: 20) {
      ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !vm.messages.isEmpty {
            if vm.hasMoreHistory && vm.hasPermission(.readMessageHistory) {
              //                PlaceholderMessageSet()
              //                  .onAppear {
              //                    vm.tryFetchMoreMessageHistory()
              //                  }
            } else {
              if vm.hasPermission(.readMessageHistory) {
                ChatHeaders.WelcomeStartOfChannelHeader()
              } else {
                ChatHeaders.NoHistoryPermissionHeader()
              }
            }
          }

          let pairs: [(DiscordChannel.Message, DiscordChannel.Message?)] = {
            var out: [(DiscordChannel.Message, DiscordChannel.Message?)] = []
            out.reserveCapacity(orderedMessages.count)
            var prior: DiscordChannel.Message? = nil
            for msg in orderedMessages {
              out.append((msg, prior))
              prior = msg
            }
            return out
          }()

          ForEach(pairs, id: \.0.id) { msg, prior in
            if msg.author?.id == nil || !blocked.contains(msg.author!.id) {
              MessageCell(
                for: msg,
                prior: prior,
                channel: vm,
                currentUserID: currentUserID,
                currentUserRoles: userRoles
              )
            }
          }

          //            if !vm.messages.isEmpty {
          //              if !vm.hasLatestMessages && vm.hasPermission(.readMessageHistory) {
          //                PlaceholderMessageSet()
          //                  .onAppear {
          //                    vm.tryFetchMoreMessageHistory()
          //                  }
          //              }
          //            } else {
          ForEach(pendingMessages.values) { message in
            // if there is only one message, there is no prior. use the latest message from channelstore
            if pendingMessages.count > 1,
              let messageIndex = pendingMessages.values.firstIndex(where: {
                $0.nonce == message.nonce
              }),
              messageIndex > 0
            {
              let priorMessage = pendingMessages.values[messageIndex - 1]
              SendMessageCell(for: message, prior: priorMessage)
            } else if let latestMessage = orderedMessages.last {
              // if there is a prior message from the channel store, use that
              SendMessageCell(for: message, prior: latestMessage)
            } else {
              // no prior message
              SendMessageCell(
                for: message,
                prior: Optional<DiscordChannel.Message>.none
              )
            }
          }
          //          }

          // message drain view, represents messages being sent etc
          Color.clear
            .frame(height: 1)
            .id(Self.bottomSentinelId)
        }
        .scrollTargetLayout()
      }
      .onAppear { self.scrollProxy = proxy }
      .id(vm.channelId)
      #if os(macOS)
        // esc to scroll to bottom of chat, its a little jank
        .focusable()
        .focusEffectDisabled()
        .onTapGesture { isChatFocused = true }
        .focused($isChatFocused)
        .onKeyPress(.escape, phases: .down) { _ in
          NotificationCenter.default.post(
            name: .chatViewShouldScrollToBottom,
            object: ["channelId": vm.channelId, "immediate": true]
          )
          return .handled
        }
      #endif
      .modifier(ChatScrollNearBottomTracker(isNearBottom: $isNearBottom))
      .bottomAnchored()
      .maxHeight(.infinity)
      .overlay(alignment: .bottomTrailing) {
        if !isNearBottom {
          Button(action: {
            NotificationCenter.default.post(
              name: .chatViewShouldScrollToBottom,
              object: ["channelId": vm.channelId, "immediate": true]
            )
          }) {
            #if os(macOS)
              Image(systemName: "arrow.down")
                .imageScale(.large)
                .padding(8)
                .glassEffect(.regular.interactive())
            #else
              Image(systemName: "arrow.down")
                .tint(.primary)
                .imageScale(.large)
                .padding(8)
                .background(.ultraThinMaterial, in: .circle)
            #endif
          }
          #if os(macOS)
            .buttonStyle(.borderless)
          #else
            .buttonStyle(.borderless)
          #endif
          .padding()
          .transition(.blurReplace.animation(.default))
        }
      }
      }  // ScrollViewReader

      #if os(iOS)
        if vm.hasPermission(.sendMessages) {
          InputBar(vm: vm)
            .id(vm.channelId)
        } else {
          Spacer().frame(height: 10)
        }
      #endif
    }
    #if os(macOS)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if vm.hasPermission(.sendMessages) {
          InputBar(vm: vm)
            .id(vm.channelId)
        }
      }
    #endif
    .animation(
      shouldAnimate && chatAnimatesMessages ? .default : nil,
      value: orderedMessages.count
    )
    .animation(chatAnimatesMessages ? .default : nil, value: pendingMessages.count)
    .scrollDismissesKeyboard(.interactively)
    .background(theme.common.secondaryBackground)
    .ignoresSafeArea(.keyboard, edges: .all)


    .toolbar {
      ToolbarItem(placement: .navigation) {
        ChannelHeader(vm: vm)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .chatViewShouldScrollToBottom
      )
    ) { object in
      guard let info = object.object as? [String: Any],
        let channelId = info["channelId"] as? ChannelSnowflake,
        channelId == vm.channelId
      else { return }
      let immediate = (info["immediate"] as? Bool == true)
      guard self.isNearBottom || immediate else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(immediate ? .default : nil) {
          self.scrollProxy?.scrollTo(Self.bottomSentinelId, anchor: .bottom)
        }
      }
    }  // handle scroll to bottom event
    .onReceive(
      NotificationCenter.default.publisher(for: .chatViewShouldScrollToID)
    ) { object in
      guard let info = object.object as? [String: Any],
        let channelId = info["channelId"] as? ChannelSnowflake,
        channelId == vm.channelId,
        let messageId = info["messageId"] as? MessageSnowflake
      else { return }
      withAnimation(.default) {
        self.scrollProxy?.scrollTo(messageId, anchor: .center)
      }
    }  // handle scroll to ID event
  }


  //  private func scheduleScrollToBottom(
  //    proxy: ScrollViewProxy,
  //    lastID: DiscordChannel.Message.ID? = nil,
  //  ) {
  //    pendingScrollWorkItem?.cancel()
  //    guard let lastID else { return }
  //
  //    let workItem = DispatchWorkItem { [proxy] in
  //      //      withAnimation(accessibilityReduceMotion ? .none : .default) {
  //      proxy.scrollTo(lastID, anchor: .top)
  //      //      }
  //    }
  //    pendingScrollWorkItem = workItem
  //    DispatchQueue.main.asyncAfter(deadline: .now(), execute: workItem)
  //  }

  @State var ackTask: Task<Void, Error>? = nil
  private func acknowledge() {
    ackTask?.cancel()
    ackTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      Task.detached {
        try await gw.client.triggerTypingIndicator(channelId: .makeFake())
      }
    }
  }
}

private struct ChatScrollNearBottomTracker: ViewModifier {
  @Binding var isNearBottom: Bool
  func body(content: Content) -> some View {
    if #available(iOS 18.0, macOS 15.0, *) {
      content.onScrollGeometryChange(for: Bool.self) { geo in
        let distanceFromBottom =
          geo.contentSize.height
          - (geo.contentOffset.y + geo.containerSize.height)
        return distanceFromBottom < 120
      } action: { _, newValue in
        if isNearBottom != newValue { isNearBottom = newValue }
      }
    } else {
      content
    }
  }
}

extension View {
  fileprivate func bottomAnchored() -> some View {
    if #available(iOS 18.0, macOS 15.0, *) {
      return
        self
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    } else {
      return
        self
        .defaultScrollAnchor(.bottom)
    }
  }
}

// add a new notification that channelstore can notify to scroll down in chat
extension Notification.Name {
  static let chatViewShouldScrollToBottom = Notification.Name(
    "chatViewShouldScrollToBottom"
  )

  static let chatViewShouldScrollToID = Notification.Name(
    "chatViewShouldScrollToID"
  )
}

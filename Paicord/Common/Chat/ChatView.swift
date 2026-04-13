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
  /// Snapshot of `last_acked_id` taken when this channel was first opened,
  /// so a new-message divider stays put while the user is reading.
  @State private var dividerAfterMessageId: MessageSnowflake? = nil
  private var blocked: Set<UserSnowflake> {
    Self.computeBlocked(from: gw.user.relationships)
  }
  private static let bottomSentinelId: String = "__paicord_bottom_sentinel__"

  private static func computeBlocked(
    from relationships: [UserSnowflake: DiscordRelationship]
  ) -> Set<UserSnowflake> {
    var s = Set<UserSnowflake>()
    for (id, rel) in relationships
    where rel.type == .blocked || rel.user_ignored {
      s.insert(id)
    }
    return s
  }

  @ViewBuilder
  private func messageRow(
    msg: DiscordChannel.Message,
    prior: DiscordChannel.Message?,
    currentUserID: UserSnowflake?,
    userRoles: [RoleSnowflake]?
  ) -> some View {
    let authorId = msg.author?.id
    let isBlocked = authorId.map { blocked.contains($0) } ?? false
    if !isBlocked {
      let showDivider: Bool = {
        guard let dividerAfterMessageId, let prior else { return false }
        return prior.id.rawValue == dividerAfterMessageId.rawValue
          && msg.id.rawValue > dividerAfterMessageId.rawValue
      }()
      if showDivider {
        NewMessagesDivider()
      }
      MessageCell(
        for: msg,
        prior: prior,
        channel: vm,
        currentUserID: currentUserID,
        currentUserRoles: userRoles
      )
    }
  }

  @ViewBuilder
  private func pendingMessageRow(
    _ tuple: (Payloads.CreateMessage, Payloads.CreateMessage?, DiscordChannel.Message?)
  ) -> some View {
    let message = tuple.0
    let priorPending = tuple.1
    let priorDelivered = tuple.2
    if let priorPending {
      SendMessageCell(for: message, prior: priorPending)
    } else if let priorDelivered {
      SendMessageCell(for: message, prior: priorDelivered)
    } else {
      SendMessageCell(
        for: message,
        prior: Optional<DiscordChannel.Message>.none
      )
    }
  }

  @ViewBuilder
  private func messagesStack(
    orderedMessages: [DiscordChannel.Message],
    pendingPairs: [(Payloads.CreateMessage, Payloads.CreateMessage?, DiscordChannel.Message?)],
    currentUserID: UserSnowflake?,
    userRoles: [RoleSnowflake]?
  ) -> some View {
    if !vm.messages.isEmpty {
      if vm.hasMoreHistory && vm.hasPermission(.readMessageHistory) {
        EmptyView()
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
      messageRow(
        msg: msg,
        prior: prior,
        currentUserID: currentUserID,
        userRoles: userRoles
      )
    }

    ForEach(0..<pendingPairs.count, id: \.self) { idx in
      pendingMessageRow(pendingPairs[idx])
    }

    Color.clear
      .frame(height: 1)
      .id(Self.bottomSentinelId)
  }

  @ViewBuilder
  private var scrollToBottomOverlay: some View {
    if !isNearBottom {
      Button {
        NotificationCenter.default.post(
          name: .chatViewShouldScrollToBottom,
          object: ["channelId": vm.channelId, "immediate": true]
        )
      } label: {
        scrollToBottomIcon
      }
      .buttonStyle(.borderless)
      .padding()
      .transition(.blurReplace.animation(.default))
    }
  }

  @ViewBuilder
  private var scrollToBottomIcon: some View {
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
    let pendingList: [Payloads.CreateMessage] = Array(pendingMessages.values)
    let pendingPairs: [(Payloads.CreateMessage, Payloads.CreateMessage?, DiscordChannel.Message?)] = {
      var out: [(Payloads.CreateMessage, Payloads.CreateMessage?, DiscordChannel.Message?)] = []
      out.reserveCapacity(pendingList.count)
      let fallback = orderedMessages.last
      for (i, m) in pendingList.enumerated() {
        if pendingList.count > 1 && i > 0 {
          out.append((m, pendingList[i - 1], nil))
        } else {
          out.append((m, nil, fallback))
        }
      }
      return out
    }()
    let currentUserID = gw.user.currentUser?.id
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
          messagesStack(
            orderedMessages: Array(orderedMessages),
            pendingPairs: pendingPairs,
            currentUserID: currentUserID,
            userRoles: userRoles
          )
        }
        .scrollTargetLayout()
      }
      .onAppear {
        self.scrollProxy = proxy
        let acked = gw.readStates.readStates[
          AnySnowflake(vm.channelId.rawValue)
        ]?.last_acked_id
        if let acked {
          self.dividerAfterMessageId = MessageSnowflake(acked.rawValue)
        }
        gw.readStates.setFocused(vm.channelId, focused: true)
      }
      .onDisappear {
        gw.readStates.setFocused(vm.channelId, focused: false)
      }
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
        scrollToBottomOverlay
      }
      }  // ScrollViewReader

      #if os(iOS)
        InputBar(vm: vm, canSend: vm.hasPermission(.sendMessages))
          .id(vm.channelId)
      #endif
    }
    #if os(macOS)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        InputBar(vm: vm, canSend: vm.hasPermission(.sendMessages))
          .id(vm.channelId)
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
      if vm.channel?.type == .dm || vm.channel?.type == .groupDm {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            Task {
              await gw.voice.joinChannel(
                channelId: vm.channelId,
                guildId: nil,
                channelName: vm.channel?.name,
                guildName: nil,
                selfVideo: false
              )
            }
          } label: {
            Image(systemName: "phone")
          }
          .disabled(gw.voice.connectedChannelId == vm.channelId)

          Button {
            Task {
              await gw.voice.joinChannel(
                channelId: vm.channelId,
                guildId: nil,
                channelName: vm.channel?.name,
                guildName: nil,
                selfVideo: true
              )
            }
          } label: {
            Image(systemName: "video")
          }
          .disabled(gw.voice.connectedChannelId == vm.channelId)
        }
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
      var tx = Transaction()
      tx.disablesAnimations = true
      withTransaction(tx) {
        self.scrollProxy?.scrollTo(Self.bottomSentinelId, anchor: .bottom)
        self.isNearBottom = true
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
      content.onScrollGeometryChange(for: CGFloat.self) { geo in
        geo.contentSize.height
          - (geo.contentOffset.y + geo.containerSize.height)
      } action: { _, distanceFromBottom in
        let threshold: CGFloat = isNearBottom ? 200 : 120
        let newValue = distanceFromBottom < threshold
        guard isNearBottom != newValue else { return }
        Task { @MainActor in
          if isNearBottom != newValue { isNearBottom = newValue }
        }
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

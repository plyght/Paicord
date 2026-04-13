//
//  InputBar.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 17/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import PhotosUI
import SwiftUIX

#if os(iOS)
  import MijickCamera
#endif

extension ChatView {
  struct InputBar: View {
    static var inputVMs: [ChannelSnowflake: InputVM] = [:]
    @Environment(\.appState) var appState
    @Environment(\.gateway) var gw
    @Environment(\.theme) var theme
    var vm: ChannelStore
    var canSend: Bool
    @State var inputVM: InputVM
    @State private var isSending: Bool = false
    @ViewStorage private var isManualUpdate = false

    static func vm(for channel: ChannelStore) -> InputVM {
      if let existingVM = InputBar.inputVMs[channel.channelId] {
        return existingVM
      } else {
        let newVM = InputVM(channelStore: channel)
        InputBar.inputVMs[channel.channelId] = newVM
        return newVM
      }
    }

    init(vm: ChannelStore, canSend: Bool = true) {
      self.vm = vm
      self.canSend = canSend
      self._inputVM = State(initialValue: InputBar.vm(for: vm))
    }

    #if os(iOS)
      struct PickerInteractionProperties {
        var storedKeyboardHeight: CGFloat = 0
        var dragOffset: CGFloat = 0
        var showPhotosPicker: Bool = false
        var showFilePicker: Bool = false
        var showEmojiPicker: Bool = false

        var keyboardHeight: CGFloat {
          storedKeyboardHeight == 0 ? 300 : storedKeyboardHeight
        }

        var pickerShown: Bool {
          showPhotosPicker || showFilePicker || showEmojiPicker
        }

        var safeArea: UIEdgeInsets {
          if let safeArea = UIApplication.shared.connectedScenes.compactMap({
            ($0 as? UIWindowScene)?.keyWindow
          }).first?.safeAreaInsets {
            return safeArea
          }
          return .zero
        }

        var screenSize: CGSize {
          if let screen = UIApplication.shared.connectedScenes.compactMap({
            ($0 as? UIWindowScene)?.screen
          }).first {
            return screen.bounds.size
          }
          return .zero
        }

        var animation: Animation {
          .interpolatingSpring(duration: 0.2, bounce: 0, initialVelocity: 0)
        }
      }

      @State private var properties = PickerInteractionProperties()

      @State var pickersClosedWhenChatClosed:
        (photos: Bool, files: Bool, emoji: Bool, keyboardFocused: Bool) = (
          false, false, false, false
        )
      @State var cameraPickerPresented: Bool = false
    #else
      @State private var fileImporterPresented: Bool = false
    #endif

    @State private var isFocused: Bool = false
    @State var filesRemovedDuringSelection: Error? = nil

    enum SelectionError: LocalizedError {
      case filesPastLimit(limit: Int)
      case filesEmpty

      var errorDescription: String? {
        switch self {
        case .filesPastLimit(let limit):
          let formatter = ByteCountFormatter()
          formatter.allowedUnits = [.useBytes, .useKB, .useMB]
          formatter.countStyle = .file
          let formattedLimit = formatter.string(fromByteCount: Int64(limit))
          return "Please keep files under \(formattedLimit)."
        case .filesEmpty:
          return "Empty files cannot be uploaded."
        }
      }
    }

    var body: some View {
      VStack(spacing: 0) {
        #if os(iOS)
          TypingIndicatorBar(vm: vm)
        #else
          TypingIndicatorBar(vm: vm)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        #endif

        VStack {
          if inputVM.uploadItems.isEmpty == false {
            AttachmentPreviewBar(inputVM: inputVM)
              .frame(height: 60)
          }

          if inputVM.messageAction != nil {
            messageActionBar
              .padding(.bottom, -4)
              .transition(
                .offset(y: 25)
                  .combined(with: .opacity)
              )
          }

          #if os(macOS)
            if inputVM.isMentioning && !inputVM.mentionResults.isEmpty {
              mentionPopover
                .transition(
                  .offset(y: 8).combined(with: .opacity)
                )
            }
            if inputVM.isSlashing {
              slashPopover
                .transition(
                  .offset(y: 8).combined(with: .opacity)
                )
            }
          #endif

          messageInputBar
        }
        .padding(.top, 4)
      }
      #if os(iOS)
        .background(.bar)
      #endif
      #if os(iOS)
        .animation(properties.animation, value: animatedKeyboardHeight)
        .animation(properties.animation, value: inputVM.content.isEmpty)
        .animation(properties.animation, value: inputVM.uploadItems.isEmpty)
      #endif
      .animation(.default, value: inputVM.messageAction.debugDescription)
      .animation(.default, value: inputVM.uploadItems)
      .onChange(of: inputVM.messageAction != nil) { _, hasAction in
        guard hasAction else { return }
        NotificationCenter.default.post(
          name: .chatViewShouldScrollToBottom,
          object: ["channelId": vm.channelId]
        )
      }
      .onChange(of: inputVM.uploadItems.count) { old, new in
        guard new > old else { return }
        NotificationCenter.default.post(
          name: .chatViewShouldScrollToBottom,
          object: ["channelId": vm.channelId]
        )
      }
      .onFileDrop(
        delegate: .init(onDrop: { droppedItems in
          let files = droppedItems.compactMap(\.loadedURL)
          inputVM.selectedFiles = filterUploadableURLs(files)
        })
      )
      #if os(macOS)
        .onDisappear {
          inputVM.clearMention()
          inputVM.clearSlash()
        }
      #endif
    }

    @ViewBuilder
    var messageInputBar: some View {
      HStack(alignment: .bottom, spacing: Spacing.standard) {
        mediaPickerButton
          .disabled(
            {
              if !canSend { return true }
              switch inputVM.messageAction {
              case .edit: return true
              default: return false
              }
            }()
          )

        if canSend {
          textField
        } else {
          noPermissionField
        }
      }
      .padding([.horizontal, .bottom], Spacing.standard)
      .padding(.top, Spacing.compact)
      .geometryGroup()
      #if os(iOS)
        .padding(.bottom, animatedKeyboardHeight)
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
          )
        ) { userInfo in
          guard isFocused else { return }
          if let keyboardFrame = userInfo.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
          ] as? NSValue {
            let height = keyboardFrame.cgRectValue.height
            properties.storedKeyboardHeight = max(
              height - properties.safeArea.bottom,
              0
            )
          }
        }  // get kb height
        .sheet(isPresented: $properties.showPhotosPicker) {
          PhotosPicker(
            "",
            selection: $inputVM.selectedPhotos,
            maxSelectionCount: 10,
            selectionBehavior: .continuous,
            preferredItemEncoding: .compatible
          )
          .photosPickerStyle(.inline)
          .photosPickerDisabledCapabilities([
            .stagingArea, .sensitivityAnalysisIntervention,
          ])
          .presentationDetents([
            .height(properties.keyboardHeight), .large,
          ])
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(properties.keyboardHeight))
          )  // allow whilst not expanded
        }
        .sheet(isPresented: $properties.showFilePicker) {
          DocumentPickerViewController { urls in
            inputVM.selectedFiles = filterUploadableURLs(urls)
          }
          .presentationBackground(.clear)
          .presentationDetents([
            .height(properties.keyboardHeight), .large,
          ])
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(properties.keyboardHeight))
          )
        }
        .sheet(isPresented: $properties.showEmojiPicker) {
          EmojiPicker()
          .presentationDetents([
            .height(properties.keyboardHeight), .large,
          ])
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(properties.keyboardHeight))
          )
        }
        .fullScreenCover(isPresented: $cameraPickerPresented) {
          MCamera()
          .setCameraOutputType(.photo)
          .setCloseMCameraAction(closeMCameraAction)
          .onImageCaptured(onImageCaptured)
          .onVideoCaptured(onVideoCaptured)
          .startSession()
        }
        .alert(
          "Some files were not added",
          isPresented: Binding(
            get: { self.filesRemovedDuringSelection != nil },
            set: { newValue in
              if newValue == false {
                self.filesRemovedDuringSelection = nil
              }
            }
          )
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          if let error = filesRemovedDuringSelection {
            Text(error.localizedDescription)
          } else {
            Text("idk bro ur files cooked")
          }
        }  // show errors for removed files
        .onChange(of: isFocused) {
          guard !isManualUpdate else { return }
          if isFocused {
            properties.showPhotosPicker = false
            properties.showFilePicker = false
            properties.showEmojiPicker = false
          }
        }  // dismiss picker when keyboard is activated
        .onChange(of: properties.pickerShown) {
          guard !isManualUpdate else { return }
          if properties.pickerShown {
            isFocused = false
          }
        }  // dismiss keyboard when picker is activated
        .onChange(of: appState.chatOpen) {
          if appState.chatOpen == false {
            pickersClosedWhenChatClosed.photos =
              properties.showPhotosPicker
            pickersClosedWhenChatClosed.files = properties.showFilePicker
            pickersClosedWhenChatClosed.emoji = properties.showEmojiPicker
            pickersClosedWhenChatClosed.keyboardFocused = isFocused
            properties.showPhotosPicker = false
            properties.showFilePicker = false
            properties.showEmojiPicker = false
            isFocused = false
          } else {
            // restore pickers if they were open before chat closed
            if pickersClosedWhenChatClosed.photos {
              properties.showPhotosPicker = true
            }
            if pickersClosedWhenChatClosed.files {
              properties.showFilePicker = true
            }
            if pickersClosedWhenChatClosed.emoji {
              properties.showEmojiPicker = true
            }
            if pickersClosedWhenChatClosed.keyboardFocused {
              isFocused = true
            }
            pickersClosedWhenChatClosed = (false, false, false, false)
          }
        }  // dismiss pickers when chat is closed
      #else
        .fileImporter(
          isPresented: $fileImporterPresented,
          allowedContentTypes: [.content],
          allowsMultipleSelection: true
        ) { result in
          do {
            let urls = try result.get()
            inputVM.selectedFiles = filterUploadableURLs(urls)
          } catch {
            print("Failed to pick files: \(error)")
          }
        }
        .fileDialogImportsUnresolvedAliases(false)
      #endif
    }

    @Namespace private var mediaPickerNamespace

    @ViewBuilder
    var mediaPickerButton: some View {
      #if os(iOS)
        if properties.pickerShown {
          Button {
            properties.showFilePicker = false
            properties.showPhotosPicker = false
            properties.showEmojiPicker = false
            // refocus keyboard
            isFocused = true
          } label: {
            Image(systemName: "plus")
              .imageScale(.large)
              .padding(Spacing.standard)
              .background(.background.secondary.opacity(0.8))
              .clipShape(.circle)
              .rotationEffect(.degrees(45))
          }
          .buttonStyle(.borderless)
          .tint(.primary)
        } else {
          Menu {
            Button {
              properties.showPhotosPicker = false
              properties.showFilePicker = false
              properties.showEmojiPicker = false
              self.cameraPickerPresented = true
            } label: {
              Label("Camera", systemImage: "camera")
            }
            Button {
              properties.showFilePicker = false
              properties.showEmojiPicker = false
              properties.showPhotosPicker = true
            } label: {
              Label("Upload Photos", systemImage: "photo.on.rectangle")
            }
            Button {
              properties.showPhotosPicker = false
              properties.showEmojiPicker = false
              properties.showFilePicker = true
            } label: {
              Label("Upload Files", systemImage: "doc.on.doc")
            }
            Menu {
              Button {
              } label: {
                Text("1")
              }
            } label: {
              Label("Apps", systemImage: "puzzlepiece.fill")
            }
          } label: {
            Image(systemName: "plus")
              .imageScale(.large)
              .padding(Spacing.standard)
              .background(.background.secondary.opacity(0.8))
              .clipShape(.circle)
          }
          .buttonStyle(.borderless)
          .tint(.primary)
        }
      #else
        Menu {
          Menu {
            Button {
            } label: {
              Text(verbatim: "1")
            }
          } label: {
            Label("Apps", systemImage: "puzzlepiece.fill")
          }

          Button {
            self.fileImporterPresented = true
          } label: {
            Label("Upload Files", systemImage: "doc.on.doc")
          }
        } label: {
          Image(systemName: "plus")
            .imageScale(.large)
            .padding(Spacing.standard)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
      #endif
    }

    @ViewBuilder
    var noPermissionField: some View {
      HStack(alignment: .center, spacing: 0) {
        Label {
          Text("You don't have permission to send messages in this channel.")
            .lineLimit(1)
            .truncationMode(.tail)
        } icon: {
          Image(systemName: "lock.fill")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
          .padding(.vertical, InputField.verticalPadding)
          .padding(.leading, InputField.horizontalPadding)
          .padding(.trailing, Spacing.standard)
        #else
          .padding(.vertical, Spacing.standard)
          .padding(.leading, Spacing.standard)
          .padding(.trailing, Spacing.compact)
        #endif

        Image(systemName: "face.smiling")
          .imageScale(.large)
          .foregroundStyle(.secondary.opacity(0.5))
          .padding(.trailing, InputField.trailingActionInset)
          .padding(.vertical, InputField.trailingActionInset)
      }
      #if os(iOS)
        .background(.background.secondary.opacity(0.8))
        .clipShape(.rect(cornerRadius: InputField.cornerRadius))
      #else
        .glassEffect(.regular.interactive())
      #endif
      .allowsHitTesting(false)
    }

    @ViewBuilder
    var textField: some View {
      HStack(alignment: .bottom) {
        #if os(iOS)
          PastableTextField(
            placeholder: "Message\(vm.channel?.name.map { " #\($0)" } ?? "")",
            text: $inputVM.content,
            isFocused: $isFocused,
            onPasteFiles: handlePastedFiles
          )
          .padding(.vertical, InputField.verticalPadding)
          .padding(.horizontal, InputField.horizontalPadding)
        #else
          TextView(
            "Message\(vm.channel?.name.map { " #\($0)" } ?? "")",
            text: $inputVM.content,
            submit: sendMessage,
            onPasteFiles: handlePastedFiles,
            inputVM: inputVM
          )
          .padding(8)
        #endif
        Button {
          #if os(iOS)
            isManualUpdate = true
            if !properties.showEmojiPicker {
              properties.showEmojiPicker = true
              isFocused = false
            } else {
              properties.showEmojiPicker = false
              properties.showFilePicker = false
              properties.showPhotosPicker = false
              isFocused = true
            }
            isManualUpdate = false
          #endif
        } label: {
          Image(systemName: "face.smiling")
            .imageScale(.large)
            .padding(.trailing, InputField.trailingActionInset)
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .padding(.vertical, InputField.trailingActionInset)
      }
      #if os(iOS)
        .background(.background.secondary.opacity(0.8))
        .clipShape(.rect(cornerRadius: InputField.cornerRadius))
      #else
        .glassEffect(.regular.interactive())
      #endif

      #if os(iOS)
        if inputVM.content.isEmpty == false
          || inputVM.uploadItems.isEmpty == false
        {
          Button(action: sendMessage) {
            Image(systemName: "paperplane.fill")
              .imageScale(.large)
              .padding(5)
              .foregroundStyle(.white)
              .background(theme.common.primaryButton)
              .clipShape(.circle)
          }
          .buttonStyle(.borderless)
          .foregroundStyle(theme.common.primaryButton)
          .transition(
            .move(edge: .trailing).combined(with: .opacity).animation(.default)
          )
        }
      #endif
    }

    #if os(iOS)
      var animatedKeyboardHeight: CGFloat {
        (properties.pickerShown || isFocused)
          ? properties.keyboardHeight : 0
      }
    #endif

    #if os(macOS)
      @ViewBuilder
      var mentionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(
            Array(inputVM.mentionResults.enumerated()),
            id: \.element.id
          ) { idx, candidate in
            mentionRow(
              candidate: candidate,
              selected: idx == inputVM.mentionSelectedIndex
            )
            .contentShape(Rectangle())
            .onTapGesture {
              inputVM.mentionSelectedIndex = idx
              inputVM.acceptMentionFromUI?()
            }
            .onHover { hovering in
              if hovering { inputVM.mentionSelectedIndex = idx }
            }
          }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 8)
        .animation(.spring(duration: 0.25), value: inputVM.mentionResults)
        .animation(
          .spring(duration: 0.2),
          value: inputVM.mentionSelectedIndex
        )
      }

      @ViewBuilder
      var slashPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
          if inputVM.slashResults.isEmpty {
            Text("No slash commands")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.vertical, 6)
              .padding(.horizontal, 8)
          } else {
            ForEach(
              Array(inputVM.slashResults.enumerated()),
              id: \.element.id
            ) { idx, candidate in
              slashRow(
                candidate: candidate,
                selected: idx == inputVM.slashSelectedIndex
              )
              .contentShape(Rectangle())
              .onTapGesture {
                inputVM.slashSelectedIndex = idx
                inputVM.acceptSlashFromUI?()
              }
              .onHover { hovering in
                if hovering { inputVM.slashSelectedIndex = idx }
              }
            }
          }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 8)
        .animation(.spring(duration: 0.25), value: inputVM.slashResults)
        .animation(
          .spring(duration: 0.2),
          value: inputVM.slashSelectedIndex
        )
        .onAppear { wireSlashExecutor() }
      }

      @ViewBuilder
      func slashRow(
        candidate: InputVM.SlashCandidate,
        selected: Bool
      ) -> some View {
        HStack(spacing: 8) {
          if let icon = candidate.applicationIcon {
            AsyncImage(
              url: URL(
                string:
                  "https://cdn.discordapp.com/app-icons/\(candidate.command.application_id.rawValue)/\(icon).png?size=32"
              )
            ) { image in
              image.resizable()
            } placeholder: {
              RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.3))
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))
          } else {
            RoundedRectangle(cornerRadius: 4)
              .fill(.secondary.opacity(0.3))
              .frame(width: 22, height: 22)
              .overlay(
                Image(systemName: "slash.circle")
                  .foregroundStyle(.secondary)
              )
          }

          Text("/\(candidate.command.name)")
            .fontWeight(.medium)
            .lineLimit(1)
          Text(candidate.command.description)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 0)
          if let app = candidate.applicationName {
            Text(app)
              .font(.caption)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle()
            .fill(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
      }

      private func wireSlashExecutor() {
        inputVM.executeSlashFromUI = { candidate in
          executeSlashCommand(candidate)
        }
      }

      private func executeSlashCommand(_ candidate: InputVM.SlashCandidate) {
        guard let channelId = appState.selectedChannel else { return }
        let guildId = vm.guildStore?.guildId
        let command = candidate.command
        Task {
          guard let manager = gw.gateway else { return }
          guard let sessionId = await manager.sessionId else {
            print("[InputBar] slash execute: no sessionId")
            return
          }
          let nonce: MessageSnowflake
          do {
            nonce = try MessageSnowflake.makeFake(date: .now)
          } catch {
            await MainActor.run { appState.error = error }
            return
          }
          let data = SlashCommandInvocation.Data(
            version: command.version ?? command.id.rawValue,
            id: command.id,
            name: command.name,
            type: 1,
            options: nil,
            attachments: [],
            application_command: command
          )
          let payload = SlashCommandInvocation(
            application_id: command.application_id,
            guild_id: guildId,
            channel_id: channelId,
            session_id: sessionId,
            data: data,
            nonce: nonce.rawValue
          )
          do {
            let resp = try await manager.client.invokeSlashCommand(
              payload: payload
            )
            try resp.guardSuccess()
          } catch {
            await MainActor.run { appState.error = error }
          }
        }
      }

      @ViewBuilder
      func mentionRow(
        candidate: InputVM.MentionCandidate,
        selected: Bool
      ) -> some View {
        HStack(spacing: 8) {
          let url = Utils.fetchUserAvatarURL(
            member: candidate.member,
            guildId: vm.guildStore?.guildId,
            user: candidate.user,
            animated: false
          )
          AsyncImage(url: url) { image in
            image.resizable()
          } placeholder: {
            Circle().fill(.secondary.opacity(0.3))
          }
          .frame(width: 22, height: 22)
          .clipShape(.circle)

          Text(candidate.displayName)
            .fontWeight(.medium)
            .lineLimit(1)
          Text("@\(candidate.user.username)")
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle()
            .fill(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
      }
    #endif

    @ViewBuilder
    var messageActionBar: some View {
      HStack {
        if let action = inputVM.messageAction {
          switch action {
          case .reply(let message, _):
            let author: Text = {
              guard let author = message.author else {
                return Text("Unknown User").bold()
              }
              if let member = vm.guildStore?.members[author.id]
                ?? message.member
              {
                return Text(
                  member.nick ?? author.global_name ?? author.username
                ).bold()
              } else {
                return Text(author.global_name ?? author.username).bold()
              }
            }()
            Text("Replying to \(author)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          case .edit(_):
            Text("Editing Message")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if case .reply(let message, let mention) = action {
            Button {
              inputVM.messageAction = .reply(
                message: message,
                mention: !mention
              )
            } label: {
              HStack(spacing: 2) {
                Image(systemName: "at")
                Text(mention ? "ON" : "OFF")
              }
              .font(.headline.bold())
            }
            .buttonStyle(.borderless)
            .tint(mention ? nil : .secondary)
          }

          Button {
            inputVM.messageAction = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .imageScale(.large)
          }
          .buttonStyle(.borderless)
          .tint(.secondary)
        }
      }
      .padding(.horizontal, 6)
      .padding(.leading, 4)
      .padding(.vertical, 4)
      #if os(iOS)
        .background(.background.secondary.opacity(0.8))
        .clipShape(.capsule)
      #else
        .glassEffect(.regular.interactive(), in: .capsule)
      #endif
      .padding(.horizontal, 8)
    }

    private func sendMessage() {
      guard !isSending else { return }
      let msg = inputVM.content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !msg.isEmpty || inputVM.uploadItems.isEmpty == false else {
        return
      }
      guard let channelId = appState.selectedChannel else { return }
      isSending = true
      // create a copy of the vm
      let toSend = inputVM.copy()
      inputVM.reset()
      Task {
        gw.messageDrain.send(toSend, in: channelId)
        await MainActor.run { isSending = false }
      }
    }

    private func filterUploadableURLs(_ urls: [URL]) -> [URL] {
      return urls.compactMap { originalURL in
        var url: URL? = originalURL
        let canAccess = url?.startAccessingSecurityScopedResource() ?? false
        defer {
          if canAccess {
            url?.stopAccessingSecurityScopedResource()
          }
        }

        let fileSize =
          (try? url?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize == 0 {
          url = nil
          self.filesRemovedDuringSelection = SelectionError.filesEmpty
        }

        let uploadMeta = gw.user.premiumKind.fileUpload(size: fileSize, to: vm)
        if uploadMeta.allowed == false {
          url = nil
          self.filesRemovedDuringSelection = SelectionError.filesPastLimit(
            limit: uploadMeta.limit
          )
        }

        return url
      }
    }

    private func handlePastedFiles(_ urls: [URL]) {
      let tempDir = FileManager.default.temporaryDirectory
      for url in urls {
        if url.path.hasPrefix(tempDir.path) {
          inputVM.trackTempFile(url)
        }
      }
      inputVM.selectedFiles = filterUploadableURLs(urls)
    }

    #if os(iOS)
      func closeMCameraAction() {
        self.cameraPickerPresented = false
      }
      func onImageCaptured(_ image: UIImage, _ controller: MCamera.Controller) {
        Task {
          let tempDir = FileManager.default.temporaryDirectory
          let fileURL = tempDir.appendingPathComponent(
            UUID().uuidString + ".png"
          )
          if let imageData = image.pngData() {
            do {
              try imageData.write(to: fileURL)
              inputVM.trackTempFile(fileURL)
              inputVM.selectedFiles.append(fileURL)
            } catch {
              print("Failed to save captured image: \(error)")
            }
          }
          controller.closeMCamera()
        }
      }
      func onVideoCaptured(_ videoURL: URL, _ controller: MCamera.Controller) {
        Task {
          let newVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
              UUID().uuidString + ".mov"
            )
          try? FileManager.default.moveItem(
            at: videoURL,
            to: newVideoURL
          )
          inputVM.trackTempFile(newVideoURL)
          inputVM.selectedFiles.append(newVideoURL)

          controller.closeMCamera()
        }
      }
    #endif
  }
}

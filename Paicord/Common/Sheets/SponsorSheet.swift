//
//  SponsorSheet.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 07/01/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import SwiftUIX

extension View {
  func sponsorSheet() -> some View {
    self
      .modifier(SponsorSheetModifier())
  }
}

extension NSNotification.Name {
  static let presentSponsorSheet =
    NSNotification.Name("Paicord.Sponsor.PresentSheet")
}

private struct SponsorSheetModifier: ViewModifier {
  @State private var isPresented: Bool = false

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $isPresented) {
        SponsorView(isPresented: $isPresented)
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: .presentSponsorSheet
        )
      ) { _ in
        isPresented = true
      }
      .onAppear {
        // set Paicord.Sponsor.InstallDate if not set
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "Paicord.Sponsor.InstallDate") == nil {
          defaults.set(Date.now, forKey: "Paicord.Sponsor.InstallDate")
        }
        // present sponsor sheet after 2 days if not presented before
        let installDate =
          defaults.object(forKey: "Paicord.Sponsor.InstallDate") as? Date
          ?? Date.now
        let hasPresented = defaults.bool(
          forKey: "Paicord.Sponsor.HasPresentedSponsorSheet"
        )
        if !hasPresented
          && Date.now.timeIntervalSince(installDate) > 2 * 24 * 60 * 60
        {
          isPresented = true
        }
      }
  }

  struct SponsorView: View {
    @Environment(\.openURL) var openURL
    @Binding var isPresented: Bool
    @State var trigger = false
    var body: some View {
      ScrollView {
        VStack {
          ZStack {
            if trigger {
              Rectangle()
                .fill(.red)
                .mask {
                  Image(systemName: "circle.dotted.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white, .clear)
                }
                .scaleEffect(1.8)
                .transition(
                  .scale.combined(with: .opacity).animation(
                    .smooth
                      .speed(0.4)
                      .delay(0.2)
                  )
                )
                .phaseAnimator([0, 360]) { content, phase in
                  content
                    .rotationEffect(.degrees(phase))
                } animation: { _ in
                  .linear(duration: 30).repeatForever(autoreverses: false)
                }

              Image(systemName: .heartCircleFill)
                .resizable()
                .scaledToFit()
                .padding(80)
                .foregroundStyle(.white, .red.gradient)
                .transition(
                  .scale.combined(with: .opacity).animation(
                    .spring(
                      response: 0.5,
                      dampingFraction: 0.6,
                      blendDuration: 0
                    )
                  )
                )
            } else {
              Group {
                Rectangle()
                  .fill(.red)
                  .mask {
                    Image(systemName: "circle.dotted.circle.fill")
                      .resizable()
                      .scaledToFit()
                      .foregroundStyle(.white, .clear)
                  }
                  .scaleEffect(1.8)
                Image(systemName: .heartCircleFill)
                  .resizable()
                  .scaledToFit()
                  .padding(80)
                  .foregroundStyle(.white, .red.gradient)
              }
              .opacity(0)
            }
          }
          .padding(.horizontal, Spacing.xLarge)
          .onTapGesture {
            trigger = false
          }

          Text("Enjoying Paicord?")
            .font(.title)
            .fontWeight(.semibold)
            .padding(.vertical, Spacing.standard)

          VStack(spacing: Spacing.medium) {
            Text(
              "Paicord is free and open source software. If you enjoy using Paicord, consider sponsoring its development to help support ongoing improvements and new features!"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Text(
              "Donors get Discord server roles, and custom profile badges visible to other Paicord users!"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .font(.subheadline)
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack {
          Text("Join the [Paicord Server](https://discord.gg/fqhPGHPyaK) to manage badges!")
            .foregroundStyle(.secondary)

          Divider()
            .padding(.horizontal, -20)

          Button {
            sponsorNow()
          } label: {
            Text("Sponsor")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.extraLarge)
          .font(.title2)
          .fontWeight(.semibold)

          Button {
            remindMeLater()
          } label: {
            Text("Remind Me Later")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.extraLarge)
          .font(.title2)
          .fontWeight(.semibold)

          Button("Never Show Again") {
            neverShowAgain()
          }
          .buttonStyle(.borderless)
          .controlSize(.large)
          .font(.title3)
          .fontWeight(.semibold)
          .padding([.horizontal, .top], Spacing.compact)
        }
        .maxWidth(.infinity)
        .padding(.horizontal, Spacing.xLarge)
        .padding(.vertical, Spacing.medium)
        .background(.thinMaterial)
      }
      .task(id: trigger) {
        try? await Task.sleep(for: .seconds(0.5))
        trigger = true
      }
    }

    func neverShowAgain() {
      let defaults = UserDefaults.standard
      defaults.set(true, forKey: "Paicord.Sponsor.HasPresentedSponsorSheet")
      self.isPresented = false
    }

    func remindMeLater() {
      let defaults = UserDefaults.standard
      defaults.set(false, forKey: "Paicord.Sponsor.HasPresentedSponsorSheet")
      self.isPresented = false
    }

    func sponsorNow() {
      let defaults = UserDefaults.standard
      defaults.set(true, forKey: "Paicord.Sponsor.HasPresentedSponsorSheet")
      let url = URL(string: "https://github.com/sponsors/llsc12")!
      self.isPresented = false
      openURL(url)
    }
  }
}

#Preview {
  SponsorSheetModifier.SponsorView(isPresented: .constant(true))
}

//
//  AboutView.swift
//  Paicord
//

#if os(macOS)
import AppKit
import SwiftUI

struct AboutView: View {
  private var appName: String {
    Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Paicord"
  }
  private var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
  }
  private var build: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
  }
  private var copyright: String? {
    Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
  }

  var body: some View {
    VStack(spacing: 0) {
      AboutIconView()
        .padding(.top, 8)

      VStack(alignment: .center, spacing: 32) {
        VStack(alignment: .center, spacing: 8) {
          Text(appName)
            .bold()
            .font(.title)
          Text("A fast, native Discord client for Apple platforms.")
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .font(.caption)
            .tint(.secondary)
            .opacity(0.8)
        }
        .textSelection(.enabled)

        VStack(spacing: 2) {
          PropertyRow(label: "Version", text: version)
          PropertyRow(label: "Build", text: build)
        }
        .textSelection(.enabled)

        if let copyright {
          Text(copyright)
            .multilineTextAlignment(.center)
            .font(.caption)
            .opacity(0.8)
        }
      }
      .padding(.top, 16)
    }
    .padding(.top, 8)
    .padding(32)
    .frame(minWidth: 300)
    .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
  }

  private struct PropertyRow: View {
    let label: String
    let text: String

    var body: some View {
      HStack(spacing: 4) {
        Text(label)
          .frame(width: 80, alignment: .trailing)
          .padding(.trailing, 2)
        Text(text)
          .frame(width: 160, alignment: .leading)
          .padding(.leading, 2)
          .tint(.secondary)
          .opacity(0.8)
          .monospaced()
      }
      .font(.callout)
    }
  }

  private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
      let v = NSVisualEffectView()
      v.autoresizingMask = [.width, .height]
      return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
      nsView.material = material
      nsView.blendingMode = blendingMode
      nsView.isEmphasized = isEmphasized
    }
  }
}

private struct AboutIconView: View {
  @State private var hovering = false
  @State private var pulse = false

  var body: some View {
    Group {
      if let nsImage = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
        Image(nsImage: nsImage)
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "app.fill")
          .resizable()
      }
    }
    .scaledToFit()
    .frame(width: 128, height: 128)
    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    .scaleEffect(hovering ? 1.04 : (pulse ? 1.01 : 1.0))
    .animation(.easeInOut(duration: 0.25), value: hovering)
    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulse)
    .onHover { hovering = $0 }
    .onAppear { pulse = true }
    .accessibilityLabel("Paicord Application Icon")
  }
}
#endif

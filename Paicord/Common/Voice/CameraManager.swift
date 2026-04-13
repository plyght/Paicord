//
//  CameraManager.swift
//  Paicord
//
//  Owns an AVCaptureSession that feeds the local camera preview in a call.
//  Requests camera permission on first start. Sending the encoded video over
//  the voice connection is not implemented — this is the local preview tier
//  of the "self video" feature.
//

import AVFoundation
import SwiftUI

@Observable
final class CameraManager: @unchecked Sendable {
  let session = AVCaptureSession()
  private(set) var isRunning = false
  private(set) var isAuthorized = false
  private let sessionQueue = DispatchQueue(label: "paicord.camera.session")

  func start() {
    requestAuthorization { [weak self] granted in
      guard let self, granted else { return }
      self.sessionQueue.async {
        self.configureIfNeeded()
        if !self.session.isRunning {
          self.session.startRunning()
        }
        DispatchQueue.main.async { self.isRunning = self.session.isRunning }
      }
    }
  }

  func stop() {
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
      DispatchQueue.main.async { self.isRunning = false }
    }
  }

  private func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      isAuthorized = true
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          self?.isAuthorized = granted
          completion(granted)
        }
      }
    default:
      isAuthorized = false
      completion(false)
    }
  }

  private var didConfigure = false
  private func configureIfNeeded() {
    guard !didConfigure else { return }
    session.beginConfiguration()
    session.sessionPreset = .medium

    #if os(iOS)
      let device = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .front
      )
    #else
      let device = AVCaptureDevice.default(for: .video)
    #endif

    if let device, let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    {
      session.addInput(input)
    }
    session.commitConfiguration()
    didConfigure = true
  }
}

struct CameraPreview: View {
  let session: AVCaptureSession
  var body: some View {
    _CameraPreviewRepresentable(session: session)
  }
}

#if os(iOS)
  import UIKit

  private struct _CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
      let v = PreviewUIView()
      v.backgroundColor = .black
      v.previewLayer.session = session
      v.previewLayer.videoGravity = .resizeAspectFill
      return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
      if uiView.previewLayer.session !== session {
        uiView.previewLayer.session = session
      }
    }
  }

  final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
      AVCaptureVideoPreviewLayer.self
    }
    var previewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }
  }
#else
  import AppKit

  private struct _CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
      let v = PreviewNSView()
      v.wantsLayer = true
      v.previewLayer.session = session
      v.previewLayer.videoGravity = .resizeAspectFill
      v.previewLayer.backgroundColor = NSColor.black.cgColor
      return v
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
      if nsView.previewLayer.session !== session {
        nsView.previewLayer.session = session
      }
    }
  }

  final class PreviewNSView: NSView {
    override func makeBackingLayer() -> CALayer {
      AVCaptureVideoPreviewLayer()
    }
    var previewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }
  }
#endif

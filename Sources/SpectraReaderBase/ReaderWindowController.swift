import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class ReaderWindowController: NSObject, NSWindowDelegate, ReaderWindowing {
  let window: NSPanel
  let viewModel: ReaderViewModel

  private let settings: SettingsStore
  private var cancellables = Set<AnyCancellable>()

  init(settings: SettingsStore, viewModel: ReaderViewModel) {
    self.settings = settings
    self.viewModel = viewModel

    let initialFrame = Self.resolveInitialFrame(settings.lensFrame)
    window = NSPanel(
      contentRect: initialFrame,
      styleMask: [.titled, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    super.init()

    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .screenSaver
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.minSize = CGSize(width: 320, height: 180)
    window.delegate = self

    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true

    let hosting = NSHostingView(
      rootView: ReaderView(viewModel: viewModel, settings: settings)
    )
    hosting.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = hosting
    window.ignoresMouseEvents = settings.allowsClickThrough

    bindSettings()
  }

  var isVisible: Bool {
    window.isVisible
  }

  var captureWindowID: CGWindowID? {
    guard window.isVisible else { return nil }
    return CGWindowID(window.windowNumber)
  }

  func show() {
    window.orderFrontRegardless()
  }

  func shutdown() {
    persistFrame()
    window.orderOut(nil)
    window.delegate = nil
    window.contentView = nil
    window.close()
  }

  func captureRectInScreen() -> CGRect {
    guard let contentView = window.contentView else {
      return window.frame
    }

    let rectInWindow = contentView.convert(contentView.bounds, to: nil)
    var rect = window.convertToScreen(rectInWindow)

    if let primaryScreenHeight = NSScreen.screens.first?.frame.height {
      rect.origin.y = primaryScreenHeight - rect.maxY
    }

    return rect
  }

  func persistFrame() {
    settings.lensFrame = window.frame
  }

  func windowDidMove(_ notification: Notification) {
    settings.lensFrame = window.frame
  }

  func windowDidResize(_ notification: Notification) {
    settings.lensFrame = window.frame
  }

  private func bindSettings() {
    settings.$allowsClickThrough
      .sink { [weak self] allowsClickThrough in
        self?.window.ignoresMouseEvents = allowsClickThrough
      }
      .store(in: &cancellables)
  }

  private static func defaultFrame() -> CGRect {
    let size = CGSize(width: 640, height: 360)
    if let screenFrame = NSScreen.main?.visibleFrame {
      let origin = CGPoint(
        x: screenFrame.midX - size.width / 2,
        y: screenFrame.midY - size.height / 2
      )
      return CGRect(origin: origin, size: size)
    }
    return CGRect(x: 200, y: 200, width: size.width, height: size.height)
  }

  private static func resolveInitialFrame(_ storedFrame: CGRect?) -> CGRect {
    let fallback = defaultFrame()
    guard let storedFrame else { return fallback }
    guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(storedFrame) }) else {
      return fallback
    }

    let visible = screen.visibleFrame
    let clampedOrigin = CGPoint(
      x: min(max(storedFrame.origin.x, visible.minX), visible.maxX - 120),
      y: min(max(storedFrame.origin.y, visible.minY), visible.maxY - 80)
    )
    let clampedSize = CGSize(
      width: min(storedFrame.width, visible.width),
      height: min(storedFrame.height, visible.height)
    )

    return CGRect(origin: clampedOrigin, size: clampedSize)
  }
}

import AppKit
import SwiftUI

@MainActor
final class AssistantWindowController: NSObject, NSWindowDelegate {
  let window: NSPanel

  private let settings: SettingsStore
  private let anchorFrameProvider: () -> CGRect
  private let viewModel: ReaderViewModel
  var onSnapshotRequested: (() -> Void)?
  var onAssistRequested: (() -> Void)?
  var settingsLauncher: (() -> Void)?

  init(
    settings: SettingsStore,
    viewModel: ReaderViewModel,
    anchorFrameProvider: @escaping () -> CGRect
  ) {
    self.settings = settings
    self.viewModel = viewModel
    self.anchorFrameProvider = anchorFrameProvider

    let initialFrame = Self.resolveInitialFrame(
      storedFrame: settings.assistantFrame,
      anchorFrame: anchorFrameProvider()
    )

    window = NSPanel(
      contentRect: initialFrame,
      styleMask: [.titled, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    super.init()

    window.title = "도움"
    window.titlebarAppearsTransparent = true
    window.level = .screenSaver
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.minSize = CGSize(width: 320, height: 260)
    window.delegate = self

    let hosting = NSHostingView(
      rootView: AssistantPanelView(
        viewModel: viewModel,
        onSnapshot: { [weak self] in
          self?.onSnapshotRequested?()
        },
        onAssist: { [weak self] in
          self?.onAssistRequested?()
        },
        onOpenSettings: { [weak self] in
          self?.settingsLauncher?()
        }
      )
    )
    hosting.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = hosting
  }

  var isVisible: Bool {
    window.isVisible
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

  func persistFrame() {
    settings.assistantFrame = window.frame
  }

  func windowDidMove(_ notification: Notification) {
    settings.assistantFrame = window.frame
  }

  func windowDidResize(_ notification: Notification) {
    settings.assistantFrame = window.frame
  }

  private static func resolveInitialFrame(storedFrame: CGRect?, anchorFrame: CGRect) -> CGRect {
    let fallback = defaultFrame(anchoredTo: anchorFrame)
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

  private static func defaultFrame(anchoredTo anchorFrame: CGRect) -> CGRect {
    let size = CGSize(width: 420, height: max(320, min(560, anchorFrame.height)))
    if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) {
      let visible = screen.visibleFrame
      let preferredX = anchorFrame.maxX + 18
      let fitsRight = preferredX + size.width <= visible.maxX
      let x = fitsRight ? preferredX : max(visible.minX, anchorFrame.minX - size.width - 18)
      let y = min(max(anchorFrame.maxY - size.height, visible.minY), visible.maxY - size.height)
      return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    return CGRect(x: anchorFrame.maxX + 18, y: anchorFrame.minY, width: size.width, height: size.height)
  }
}

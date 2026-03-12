import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
  init(settings: SettingsStore) {
    let view = SettingsView(settings: settings)
    let hosting = NSHostingView(rootView: view)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.center()
    window.title = "Settings"
    window.contentView = hosting

    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

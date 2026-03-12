import AppKit

@MainActor
final class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let onToggleReader: () -> Void
  private let onShowSettings: () -> Void

  init(
    onToggleReader: @escaping () -> Void,
    onShowSettings: @escaping () -> Void
  ) {
    self.onToggleReader = onToggleReader
    self.onShowSettings = onShowSettings
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    super.init()

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Reader")
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.addItem(makeItem(title: "Reader On/Off", action: #selector(toggleReader)))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(makeItem(title: "Settings", action: #selector(showSettings)))
    menu.addItem(makeItem(title: "Quit", action: #selector(quit)))
    statusItem.menu = menu
  }

  private func makeItem(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func toggleReader() {
    onToggleReader()
  }

  @objc private func showSettings() {
    onShowSettings()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}

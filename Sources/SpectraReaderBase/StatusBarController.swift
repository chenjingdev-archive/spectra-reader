import AppKit

@MainActor
final class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let onToggleReader: () -> Void
  private let onSnapshotNow: () -> Void
  private let onAssistNow: () -> Void
  private let onResetNow: () -> Void
  private let onShowSettings: () -> Void

  init(
    onToggleReader: @escaping () -> Void,
    onSnapshotNow: @escaping () -> Void,
    onAssistNow: @escaping () -> Void,
    onResetNow: @escaping () -> Void,
    onShowSettings: @escaping () -> Void
  ) {
    self.onToggleReader = onToggleReader
    self.onSnapshotNow = onSnapshotNow
    self.onAssistNow = onAssistNow
    self.onResetNow = onResetNow
    self.onShowSettings = onShowSettings
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    super.init()

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "리더")
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.addItem(makeItem(title: "리더 켜기/끄기", action: #selector(toggleReader)))
    menu.addItem(makeItem(title: "스냅샷 누적", action: #selector(snapshotNow)))
    menu.addItem(makeItem(title: "도움 실행", action: #selector(assistNow)))
    menu.addItem(makeItem(title: "누적 초기화", action: #selector(resetNow)))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(makeItem(title: "설정", action: #selector(showSettings)))
    menu.addItem(makeItem(title: "종료", action: #selector(quit)))
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

  @objc private func snapshotNow() {
    onSnapshotNow()
  }

  @objc private func assistNow() {
    onAssistNow()
  }

  @objc private func resetNow() {
    onResetNow()
  }

  @objc private func showSettings() {
    onShowSettings()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}

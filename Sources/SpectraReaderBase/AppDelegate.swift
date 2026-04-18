import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = SettingsStore()
  private var runtimeManager: ReaderRuntimeManager!
  private var statusBarController: StatusBarController!
  private var settingsWindowController: SettingsWindowController!
  private var globalEventMonitor: Any?
  private var localEventMonitor: Any?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    settingsWindowController = SettingsWindowController(settings: settings)
    runtimeManager = ReaderRuntimeManager(
      settings: settings,
      openSettings: { [weak self] in
        self?.settingsWindowController.show()
      }
    )

    statusBarController = StatusBarController(
      onToggleReader: { [weak self] in
        self?.runtimeManager.toggle()
      },
      onSnapshotNow: { [weak self] in
        self?.runtimeManager.read()
      },
      onAssistNow: { [weak self] in
        self?.runtimeManager.assist()
      },
      onResetNow: { [weak self] in
        self?.runtimeManager.resetReadingSession()
      },
      onShowSettings: { [weak self] in
        self?.settingsWindowController.show()
      }
    )

    setupGlobalHotkeyObservers()
    setupGlobalHotkey()
    runtimeManager.show()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    setupGlobalHotkey()
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtimeManager?.hide()

    if let monitor = globalEventMonitor {
      NSEvent.removeMonitor(monitor)
      globalEventMonitor = nil
    }

    if let monitor = localEventMonitor {
      NSEvent.removeMonitor(monitor)
      localEventMonitor = nil
    }
  }

  private func setupGlobalHotkeyObservers() {
    settings.$snapshotHotkey
      .combineLatest(settings.$assistHotkey, settings.$resetHotkey)
      .sink { [weak self] _, _, _ in
        self?.setupGlobalHotkey()
      }
      .store(in: &cancellables)
  }

  private func setupGlobalHotkey() {
    if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
    globalEventMonitor = nil
    localEventMonitor = nil

    let hotkeys = configuredHotkeys()
    if hotkeys.isEmpty {
      return
    }

    if hotkeys.contains(where: { !$0.hotkey.isEmpty }) && !AccessibilityPermission.isTrusted() {
      PermissionPrompter.shared.requestAccessibilityForHotkeysIfNeeded()
    }

    let globalHandler: (NSEvent) -> Void = { [weak self] event in
      self?.handleHotkeyEvent(event)
    }

    let localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
      if self?.handleHotkeyEvent(event) == true {
        return nil
      }
      return event
    }

    globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: globalHandler)
    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: localHandler)
  }

  private func configuredHotkeys() -> [(hotkey: HotkeyBinding, action: () -> Void)] {
    [
      (
        hotkey: settings.snapshotHotkey,
        action: { [weak self] in self?.runtimeManager.read() }
      ),
      (
        hotkey: settings.assistHotkey,
        action: { [weak self] in self?.runtimeManager.assist() }
      ),
      (
        hotkey: settings.resetHotkey,
        action: { [weak self] in self?.runtimeManager.resetReadingSession() }
      )
    ]
    .filter { !$0.hotkey.isEmpty }
  }

  @discardableResult
  private func handleHotkeyEvent(_ event: NSEvent) -> Bool {
    guard let match = configuredHotkeys().first(where: { matches(event: event, hotkey: $0.hotkey) }) else {
      return false
    }

    match.action()
    return true
  }

  private func matches(event: NSEvent, hotkey: HotkeyBinding) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let targetFlags = NSEvent.ModifierFlags(rawValue: hotkey.modifiers)

    if hotkey.keyCode == -1 {
      return event.type == .flagsChanged && flags == targetFlags
    }

    return event.type == .keyDown &&
      Int(event.keyCode) == hotkey.keyCode &&
      flags.isSuperset(of: targetFlags)
  }
}

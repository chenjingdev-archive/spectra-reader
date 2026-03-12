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
    settings.$hotkeyModifiers
      .combineLatest(settings.$hotkeyKeyCode)
      .sink { [weak self] _, _ in
        self?.setupGlobalHotkey()
      }
      .store(in: &cancellables)
  }

  private func setupGlobalHotkey() {
    if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
    globalEventMonitor = nil
    localEventMonitor = nil

    let targetFlags = NSEvent.ModifierFlags(rawValue: settings.hotkeyModifiers)
    let targetKey = settings.hotkeyKeyCode

    if targetKey == -1 && targetFlags.isEmpty {
      return
    }

    if !AccessibilityPermission.isTrusted() {
      PermissionPrompter.shared.requestAccessibilityForHotkeysIfNeeded()
    }

    if targetKey == -1 {
      let handler: (NSEvent) -> Void = { [weak self] event in
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == targetFlags {
          self?.runtimeManager.toggle()
        }
      }

      globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
      localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
        handler(event)
        return event
      }
      return
    }

    let callback: () -> Void = { [weak self] in
      Task { @MainActor in
        self?.runtimeManager.toggle()
      }
    }

    let globalHandler: (NSEvent) -> Void = { event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if event.keyCode == targetKey && flags.isSuperset(of: targetFlags) {
        callback()
      }
    }

    let localHandler: (NSEvent) -> NSEvent? = { event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if event.keyCode == targetKey && flags.isSuperset(of: targetFlags) {
        callback()
        return nil
      }
      return event
    }

    globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: globalHandler)
    localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: localHandler)
  }
}

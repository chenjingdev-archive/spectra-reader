import AppKit

@MainActor
protocol ReaderRuntime: AnyObject {
  var isVisible: Bool { get }

  func show()
  func persistWindowState()
  func stopReader(clearContent: Bool)
  func shutdownWindow()
}

@MainActor
final class DefaultReaderRuntime: ReaderRuntime {
  private let settings: SettingsStore
  private let readerWindow: ReaderWindowController
  private let readerCoordinator: ReaderCoordinator

  init(settings: SettingsStore, openSettings: @escaping () -> Void) {
    self.settings = settings
    readerWindow = ReaderWindowController(settings: settings)
    readerCoordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: readerWindow
    )

    readerWindow.settingsLauncher = openSettings
    readerWindow.onMoveEnd = { [weak self] in
      guard let self else { return }
      guard self.settings.readerEnabled else { return }
      self.readerCoordinator.readNow(trigger: .moveEnd)
    }
  }

  var isVisible: Bool {
    readerWindow.isVisible
  }

  func show() {
    readerWindow.show()
    readerCoordinator.startIfNeeded()
    readerCoordinator.readNow(trigger: .manual)
  }

  func persistWindowState() {
    readerWindow.persistFrame()
  }

  func stopReader(clearContent: Bool) {
    readerCoordinator.stop(clearContent: clearContent)
  }

  func shutdownWindow() {
    readerWindow.shutdown()
  }
}

@MainActor
final class ReaderRuntimeManager {
  private let makeRuntime: () -> ReaderRuntime
  private var runtime: ReaderRuntime?

  init(makeRuntime: @escaping () -> ReaderRuntime) {
    self.makeRuntime = makeRuntime
  }

  convenience init(settings: SettingsStore, openSettings: @escaping () -> Void) {
    self.init {
      DefaultReaderRuntime(settings: settings, openSettings: openSettings)
    }
  }

  var isVisible: Bool {
    runtime?.isVisible ?? false
  }

  func show() {
    if let runtime {
      runtime.show()
      return
    }

    let runtime = makeRuntime()
    self.runtime = runtime
    runtime.show()
  }

  func hide() {
    guard let runtime else { return }
    runtime.persistWindowState()
    runtime.stopReader(clearContent: true)
    runtime.shutdownWindow()
    self.runtime = nil
  }

  func toggle() {
    if isVisible {
      hide()
    } else {
      show()
    }
  }
}

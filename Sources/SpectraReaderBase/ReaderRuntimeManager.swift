import AppKit

@MainActor
protocol ReaderRuntime: AnyObject {
  var isVisible: Bool { get }

  func show()
  func readNow()
  func assistNow()
  func persistWindowState()
  func stopReader(clearContent: Bool)
  func shutdownWindow()
}

@MainActor
final class DefaultReaderRuntime: ReaderRuntime {
  private let settings: SettingsStore
  private let viewModel: ReaderViewModel
  private let readerWindow: ReaderWindowController
  private let assistantWindow: AssistantWindowController
  private let readerCoordinator: ReaderCoordinator

  init(settings: SettingsStore, openSettings: @escaping () -> Void) {
    self.settings = settings
    viewModel = ReaderViewModel()
    let overlayWindow = ReaderWindowController(settings: settings, viewModel: viewModel)
    readerWindow = overlayWindow
    assistantWindow = AssistantWindowController(
      settings: settings,
      viewModel: viewModel,
      anchorFrameProvider: { overlayWindow.window.frame }
    )
    readerCoordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: overlayWindow
    )

    assistantWindow.settingsLauncher = openSettings
    assistantWindow.onReadRequested = { [weak self] in
      _ = self?.readerCoordinator.readNow()
    }
    assistantWindow.onAssistRequested = { [weak self] in
      _ = self?.readerCoordinator.assistNow()
    }
  }

  var isVisible: Bool {
    readerWindow.isVisible || assistantWindow.isVisible
  }

  func show() {
    readerWindow.show()
    assistantWindow.show()
    readerCoordinator.startIfNeeded()
  }

  func readNow() {
    show()
    _ = readerCoordinator.readNow()
  }

  func assistNow() {
    show()
    _ = readerCoordinator.assistNow()
  }

  func persistWindowState() {
    readerWindow.persistFrame()
    assistantWindow.persistFrame()
  }

  func stopReader(clearContent: Bool) {
    readerCoordinator.stop(clearContent: clearContent)
  }

  func shutdownWindow() {
    readerWindow.shutdown()
    assistantWindow.shutdown()
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

  func read() {
    if let runtime {
      runtime.readNow()
      return
    }

    let runtime = makeRuntime()
    self.runtime = runtime
    runtime.readNow()
  }

  func assist() {
    if let runtime {
      runtime.assistNow()
      return
    }

    let runtime = makeRuntime()
    self.runtime = runtime
    runtime.assistNow()
  }
}

import AppKit
import Combine

enum ReaderTrigger {
  case manual
  case moveEnd
  case interval
}

@MainActor
final class ReaderCoordinator {
  private let settings: SettingsStore
  private let readerWindow: ReaderWindowing
  private let captureService: ScreenCapturing
  private let ocrService: OCRRecognizing
  private let permissionPrompter: ScreenRecordingPrompting
  private let screenCaptureAuthorizer: ScreenCaptureAuthorizing
  private let pipelineTimeout: TimeInterval

  private var isStarted = false
  private var isRunning = false
  private var intervalTimer: Timer?
  private var currentTask: Task<Void, Never>?
  private var currentTaskID: UUID?
  private var timeoutWorkItem: DispatchWorkItem?
  private var cancellables = Set<AnyCancellable>()

  init(
    settings: SettingsStore,
    readerWindow: ReaderWindowing,
    captureService: ScreenCapturing = ScreenCaptureService(),
    ocrService: OCRRecognizing = OCRService(),
    permissionPrompter: ScreenRecordingPrompting? = nil,
    screenCaptureAuthorizer: ScreenCaptureAuthorizing = ScreenCaptureAuthorization(),
    pipelineTimeout: TimeInterval = 8.0
  ) {
    self.settings = settings
    self.readerWindow = readerWindow
    self.captureService = captureService
    self.ocrService = ocrService
    self.permissionPrompter = permissionPrompter ?? PermissionPrompter.shared
    self.screenCaptureAuthorizer = screenCaptureAuthorizer
    self.pipelineTimeout = pipelineTimeout

    settings.$intervalEnabled
      .sink { [weak self] _ in
        self?.handleIntervalSettingsChanged()
      }
      .store(in: &cancellables)

    settings.$intervalSeconds
      .sink { [weak self] _ in
        self?.handleIntervalSettingsChanged()
      }
      .store(in: &cancellables)

    settings.$readerEnabled
      .sink { [weak self] enabled in
        self?.handleReaderToggle(enabled)
      }
      .store(in: &cancellables)
  }

  func startIfNeeded() {
    guard !isStarted else { return }
    isStarted = true
    configureInterval()
  }

  func stop(clearContent: Bool = true) {
    intervalTimer?.invalidate()
    intervalTimer = nil

    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false

    if clearContent {
      clearViewModel(status: "Idle")
    } else if readerWindow.viewModel.statusText == "Scanning" {
      readerWindow.viewModel.statusText = "Idle"
    }
  }

  func readNow(trigger: ReaderTrigger = .manual) {
    guard isStarted else { return }

    if !settings.readerEnabled {
      clearViewModel(status: "Idle")
      return
    }

    guard readerWindow.isVisible else { return }
    guard !isRunning else { return }

    if !screenCaptureAuthorizer.hasAccess() {
      if shouldPromptForScreenCapturePermission(for: trigger) {
        permissionPrompter.requestScreenRecordingIfNeeded()
      }
      readerWindow.viewModel.statusText = "No Permission"
      readerWindow.viewModel.isBusy = false
      return
    }

    guard let windowID = readerWindow.captureWindowID else { return }

    isRunning = true
    readerWindow.viewModel.isBusy = true
    readerWindow.viewModel.statusText = "Scanning"

    let windowFrame = readerWindow.captureRectInScreen()
    let captureService = self.captureService
    let ocrService = self.ocrService
    let screenCaptureAuthorizer = self.screenCaptureAuthorizer
    let taskID = UUID()

    currentTask?.cancel()
    currentTaskID = taskID
    scheduleTimeout(for: taskID)
    currentTask = Task.detached(priority: .userInitiated) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          self?.finishRun(taskID: taskID)
        }
      }

      guard let self else { return }

      do {
        try Task.checkCancellation()

        if !screenCaptureAuthorizer.hasAccess() {
          await MainActor.run {
            self.applyIfCurrent(taskID: taskID) {
              self.readerWindow.viewModel.statusText = "No Permission"
            }
          }
          return
        }

        guard let image = captureService.capture(rect: windowFrame, below: windowID) else {
          await MainActor.run {
            self.applyIfCurrent(taskID: taskID) {
              self.readerWindow.viewModel.statusText = "Capture Failed"
            }
          }
          return
        }

        try Task.checkCancellation()
        let blocks = try ocrService.recognizeTextBlocks(in: image)
        try Task.checkCancellation()

        if blocks.isEmpty {
          await MainActor.run {
            self.applyIfCurrent(taskID: taskID) {
              self.clearViewModel(status: "No Text Found")
            }
          }
          return
        }

        let recognizedText = blocks.map(\.text).joined(separator: "\n")

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.readerWindow.viewModel.recognizedBlocks = blocks
            self.readerWindow.viewModel.recognizedText = recognizedText
            self.readerWindow.viewModel.statusText = "Updated"
          }
        }
      } catch is CancellationError {
        return
      } catch {
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.clearViewModel(status: "OCR Error")
          }
        }
      }
    }
  }

  private func handleIntervalSettingsChanged() {
    guard isStarted else { return }
    configureInterval()
  }

  private func configureInterval() {
    intervalTimer?.invalidate()
    intervalTimer = nil

    guard isStarted, settings.intervalEnabled, settings.readerEnabled else { return }

    let interval = max(1.0, settings.intervalSeconds)
    intervalTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.readNow(trigger: .interval)
      }
    }
    intervalTimer?.tolerance = interval * 0.1
  }

  private func handleReaderToggle(_ enabled: Bool) {
    guard isStarted else { return }

    if enabled {
      configureInterval()
      return
    }

    stop(clearContent: true)
  }

  private func clearViewModel(status: String) {
    readerWindow.viewModel.recognizedBlocks = []
    readerWindow.viewModel.recognizedText = ""
    readerWindow.viewModel.statusText = status
    readerWindow.viewModel.isBusy = false
  }

  private func shouldPromptForScreenCapturePermission(for trigger: ReaderTrigger) -> Bool {
    switch trigger {
    case .manual:
      return true
    case .moveEnd, .interval:
      return false
    }
  }

  private func scheduleTimeout(for taskID: UUID) {
    timeoutWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.handleTimeout(taskID: taskID)
    }
    timeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + pipelineTimeout, execute: workItem)
  }

  private func handleTimeout(taskID: UUID) {
    guard currentTaskID == taskID else { return }

    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    timeoutWorkItem = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    clearViewModel(status: "Timed Out")
  }

  private func applyIfCurrent(taskID: UUID, _ updates: () -> Void) {
    guard currentTaskID == taskID else { return }
    updates()
  }

  private func finishRun(taskID: UUID) {
    guard currentTaskID == taskID else { return }
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    currentTask = nil
    currentTaskID = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false

    if readerWindow.viewModel.statusText == "Scanning" {
      readerWindow.viewModel.statusText = "Idle"
    }
  }
}

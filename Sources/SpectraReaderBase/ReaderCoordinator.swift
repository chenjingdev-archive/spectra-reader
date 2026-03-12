import AppKit
import Combine

@MainActor
final class ReaderCoordinator {
  private let settings: SettingsStore
  private let readerWindow: ReaderWindowing
  private let captureService: ScreenCapturing
  private let ocrService: OCRRecognizing
  private let assistantProviderFactory: @Sendable (String) -> any AssistantProviding
  private let permissionPrompter: ScreenRecordingPrompting
  private let screenCaptureAuthorizer: ScreenCaptureAuthorizing
  private let pipelineTimeout: TimeInterval
  private let assistantPipelineTimeout: TimeInterval
  private let snapshotFreshnessWindow: TimeInterval

  private var isStarted = false
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var currentTaskID: UUID?
  private var timeoutWorkItem: DispatchWorkItem?
  private var currentSnapshot: ReadingSnapshot?
  private var cancellables = Set<AnyCancellable>()

  init(
    settings: SettingsStore,
    readerWindow: ReaderWindowing,
    captureService: ScreenCapturing = ScreenCaptureService(),
    ocrService: OCRRecognizing = OCRService(),
    assistantProviderFactory: @escaping @Sendable (String) -> any AssistantProviding = {
      HelperAssistantService(command: $0)
    },
    permissionPrompter: ScreenRecordingPrompting? = nil,
    screenCaptureAuthorizer: ScreenCaptureAuthorizing = ScreenCaptureAuthorization(),
    pipelineTimeout: TimeInterval = 15.0,
    assistantPipelineTimeout: TimeInterval = 180.0,
    snapshotFreshnessWindow: TimeInterval = 10.0
  ) {
    self.settings = settings
    self.readerWindow = readerWindow
    self.captureService = captureService
    self.ocrService = ocrService
    self.assistantProviderFactory = assistantProviderFactory
    self.permissionPrompter = permissionPrompter ?? PermissionPrompter.shared
    self.screenCaptureAuthorizer = screenCaptureAuthorizer
    self.pipelineTimeout = pipelineTimeout
    self.assistantPipelineTimeout = max(assistantPipelineTimeout, pipelineTimeout)
    self.snapshotFreshnessWindow = snapshotFreshnessWindow

    settings.$selectedPresetID
      .combineLatest(settings.$presets)
      .sink { [weak self] _, _ in
        self?.syncPresetName()
      }
      .store(in: &cancellables)
  }

  func startIfNeeded() {
    guard !isStarted else { return }
    isStarted = true
    syncPresetName()
    readerWindow.viewModel.statusText = "준비됨"
  }

  func stop(clearContent: Bool = true) {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    currentSnapshot = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false

    if clearContent {
      clearViewModel(status: "준비됨")
    } else if readerWindow.viewModel.statusText == "읽는 중" || readerWindow.viewModel.statusText == "도움 생성 중" {
      readerWindow.viewModel.statusText = "준비됨"
    }
  }

  @discardableResult
  func readNow() -> Task<Void, Never>? {
    guard isStarted else { return nil }
    guard readerWindow.isVisible else { return nil }
    guard !isRunning else { return currentTask }

    if !screenCaptureAuthorizer.hasAccess() {
      permissionPrompter.requestScreenRecordingIfNeeded()
      clearViewModel(status: "권한 필요")
      return nil
    }

    guard let windowID = readerWindow.captureWindowID else { return nil }

    let sourceRect = readerWindow.captureRectInScreen()
    let taskID = UUID()
    let captureService = self.captureService
    let ocrService = self.ocrService
    let screenCaptureAuthorizer = self.screenCaptureAuthorizer

    beginTask(taskID: taskID, status: "읽는 중", timeout: pipelineTimeout)
    currentTask = Task.detached(priority: .userInitiated) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          self?.finishRun(taskID: taskID)
        }
      }

      guard let self else { return }

      do {
        let snapshot = try Self.performOCR(
          captureService: captureService,
          ocrService: ocrService,
          screenCaptureAuthorizer: screenCaptureAuthorizer,
          sourceRect: sourceRect,
          windowID: windowID
        )

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.applySnapshot(snapshot, status: "준비됨")
          }
        }
      } catch is CancellationError {
        return
      } catch let error as ReaderPipelineError {
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.handlePipelineError(error)
          }
        }
      } catch {
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.handlePipelineError(.ocrFailed)
          }
        }
      }
    }

    return currentTask
  }

  @discardableResult
  func assistNow() -> Task<Void, Never>? {
    guard isStarted else { return nil }
    guard readerWindow.isVisible else { return nil }
    guard !isRunning else { return currentTask }

    if !screenCaptureAuthorizer.hasAccess() {
      permissionPrompter.requestScreenRecordingIfNeeded()
      clearViewModel(status: "권한 필요")
      return nil
    }

    guard let preset = settings.selectedPreset else {
      setAssistantUnavailable("먼저 프리셋을 선택하세요.")
      return nil
    }

    let command = settings.helperCommandPath
    let sourceRect = readerWindow.captureRectInScreen()

    if let snapshot = reusableSnapshot(for: sourceRect) {
      return startAssistantTask(snapshot: snapshot, preset: preset, command: command)
    }

    guard let windowID = readerWindow.captureWindowID else { return nil }

    let taskID = UUID()
    let captureService = self.captureService
    let ocrService = self.ocrService
    let screenCaptureAuthorizer = self.screenCaptureAuthorizer
    let assistantFactory = self.assistantProviderFactory

    beginTask(taskID: taskID, status: "읽는 중", timeout: assistantPipelineTimeout)
    currentTask = Task.detached(priority: .userInitiated) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          self?.finishRun(taskID: taskID)
        }
      }

      guard let self else { return }

      do {
        let snapshot = try Self.performOCR(
          captureService: captureService,
          ocrService: ocrService,
          screenCaptureAuthorizer: screenCaptureAuthorizer,
          sourceRect: sourceRect,
          windowID: windowID
        )

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.applySnapshot(snapshot, status: "도움 생성 중")
            self.readerWindow.viewModel.isBusy = true
          }
        }

        let provider = assistantFactory(command)
        let result = try await provider.run(snapshot: snapshot, preset: preset)

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.applyAssistantResult(result)
          }
        }
      } catch is CancellationError {
        return
      } catch let error as ReaderPipelineError {
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.handlePipelineError(error)
          }
        }
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.setAssistantUnavailable(message)
          }
        }
      }
    }

    return currentTask
  }

  private func beginTask(taskID: UUID, status: String, timeout: TimeInterval) {
    timeoutWorkItem?.cancel()
    currentTask?.cancel()
    currentTaskID = taskID
    isRunning = true
    readerWindow.viewModel.isBusy = true
    readerWindow.viewModel.statusText = status
    scheduleTimeout(for: taskID, timeout: timeout)
  }

  private func syncPresetName() {
    readerWindow.viewModel.currentPresetName = settings.selectedPreset?.name ?? "프리셋"
  }

  private func reusableSnapshot(for sourceRect: CGRect) -> ReadingSnapshot? {
    guard let snapshot = currentSnapshot else { return nil }
    guard Date().timeIntervalSince(snapshot.capturedAt) <= snapshotFreshnessWindow else { return nil }
    guard Self.rectsApproximatelyEqual(snapshot.sourceRect, sourceRect) else { return nil }
    return snapshot
  }

  private func clearViewModel(status: String) {
    currentSnapshot = nil
    readerWindow.viewModel.recognizedBlocks = []
    readerWindow.viewModel.recognizedText = ""
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.lastSnapshotAt = nil
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = status
    readerWindow.viewModel.isBusy = false
  }

  private func applySnapshot(_ snapshot: ReadingSnapshot, status: String) {
    currentSnapshot = snapshot
    readerWindow.viewModel.recognizedBlocks = snapshot.blocks
    readerWindow.viewModel.recognizedText = snapshot.plainText
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.lastSnapshotAt = snapshot.capturedAt
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = status
  }

  private func applyAssistantResult(_ result: AssistantResult) {
    readerWindow.viewModel.assistantText = result.outputText
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = "준비됨"
  }

  private func setAssistantUnavailable(_ message: String) {
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.lastError = message
    readerWindow.viewModel.statusText = "도움 사용 불가"
    readerWindow.viewModel.isBusy = false
  }

  private func handlePipelineError(_ error: ReaderPipelineError) {
    switch error {
    case .noPermission:
      clearViewModel(status: "권한 필요")
    case .captureFailed:
      clearViewModel(status: "캡처 실패")
    case .noTextFound:
      clearViewModel(status: "텍스트 없음")
    case .ocrFailed:
      clearViewModel(status: "OCR 오류")
    }
  }

  private func startAssistantTask(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    command: String
  ) -> Task<Void, Never> {
    let taskID = UUID()
    let assistantFactory = self.assistantProviderFactory

    beginTask(taskID: taskID, status: "도움 생성 중", timeout: assistantPipelineTimeout)
    currentTask = Task.detached(priority: .userInitiated) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          self?.finishRun(taskID: taskID)
        }
      }

      guard let self else { return }

      do {
        let provider = assistantFactory(command)
        let result = try await provider.run(snapshot: snapshot, preset: preset)

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.applyAssistantResult(result)
          }
        }
      } catch is CancellationError {
        return
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.setAssistantUnavailable(message)
          }
        }
      }
    }

    return currentTask!
  }

  private func scheduleTimeout(for taskID: UUID, timeout: TimeInterval) {
    timeoutWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.handleTimeout(taskID: taskID)
    }
    timeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
  }

  private func handleTimeout(taskID: UUID) {
    guard currentTaskID == taskID else { return }

    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    timeoutWorkItem = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.lastError = "작업 시간이 초과되었습니다."
    readerWindow.viewModel.statusText = "시간 초과"
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
  }

  nonisolated private static func performOCR(
    captureService: ScreenCapturing,
    ocrService: OCRRecognizing,
    screenCaptureAuthorizer: ScreenCaptureAuthorizing,
    sourceRect: CGRect,
    windowID: CGWindowID
  ) throws -> ReadingSnapshot {
    try Task.checkCancellation()

    if !screenCaptureAuthorizer.hasAccess() {
      throw ReaderPipelineError.noPermission
    }

    guard let image = captureService.capture(rect: sourceRect, below: windowID) else {
      throw ReaderPipelineError.captureFailed
    }

    try Task.checkCancellation()
    let blocks = try ocrService.recognizeTextBlocks(in: image)
    try Task.checkCancellation()

    guard !blocks.isEmpty else {
      throw ReaderPipelineError.noTextFound
    }

    let plainText = blocks.map(\.text).joined(separator: "\n")
    return ReadingSnapshot(blocks: blocks, plainText: plainText, sourceRect: sourceRect)
  }

  nonisolated private static func rectsApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2.0) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
      abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
      abs(lhs.size.width - rhs.size.width) <= tolerance &&
      abs(lhs.size.height - rhs.size.height) <= tolerance
  }
}

private enum ReaderPipelineError: Error {
  case noPermission
  case captureFailed
  case noTextFound
  case ocrFailed
}

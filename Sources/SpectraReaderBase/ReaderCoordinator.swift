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
  private var currentOperation: ReaderOperation?
  private var timeoutWorkItem: DispatchWorkItem?
  private var currentSnapshot: ReadingSnapshot?
  private var readingSession: ReadingSession?
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
    currentOperation = nil
    currentSnapshot = nil
    readingSession = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false

    if clearContent {
      clearCurrentReading()
      clearReadingSession()
      readerWindow.viewModel.lastError = nil
      readerWindow.viewModel.statusText = "준비됨"
    } else if readerWindow.viewModel.statusText != "준비됨" {
      readerWindow.viewModel.statusText = "준비됨"
    }
  }

  @discardableResult
  func cancelAssistIfRunning() -> Bool {
    guard currentOperation == .assistCurrent || currentOperation == .assistSession else {
      return false
    }

    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    currentOperation = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = nil
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = "도움 취소됨"
    return true
  }

  @discardableResult
  func readNow() -> Task<Void, Never>? {
    readMoreNow()
  }

  @discardableResult
  func readMoreNow() -> Task<Void, Never>? {
    guard canStartInteractiveTask() else { return currentTask }

    guard screenCaptureAuthorizer.hasAccess() else {
      handlePermissionDenied(for: .append)
      return nil
    }

    guard let captureContext = captureContext() else { return nil }
    let taskID = UUID()
    let captureService = self.captureService
    let ocrService = self.ocrService
    let screenCaptureAuthorizer = self.screenCaptureAuthorizer

    beginTask(taskID: taskID, operation: .append, status: "스냅샷 읽는 중", timeout: pipelineTimeout)
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
          sourceRect: captureContext.sourceRect,
          windowID: captureContext.windowID
        )

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            self.applySnapshot(snapshot, status: "스냅샷 정리 중")
            self.appendSnapshotToReadingSession(snapshot)
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
            self.handleUnexpectedPipelineError(message)
          }
        }
      }
    }

    return currentTask
  }

  @discardableResult
  func assistNow() -> Task<Void, Never>? {
    assistSessionNow()
  }

  @discardableResult
  func assistSessionNow() -> Task<Void, Never>? {
    guard canStartInteractiveTask() else { return currentTask }

    guard let preset = settings.selectedPreset else {
      setSessionAssistantUnavailable("먼저 프리셋을 선택하세요.")
      return nil
    }

    guard let session = readingSession, session.hasContent else {
      setSessionAssistantUnavailable("먼저 '스냅샷'으로 원문을 쌓으세요.")
      return nil
    }

    let sourceRect = readerWindow.captureRectInScreen()
    let snapshot = session.asSnapshot(sourceRect: sourceRect)
    return startAssistantTask(
      snapshot: snapshot,
      preset: preset,
      command: settings.helperCommandPath,
      kind: .session
    )
  }

  func resetReadingSession() {
    guard !isRunning else { return }
    clearSnapshotBuffer()
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = "스냅샷 비움"
  }

  private func canStartInteractiveTask() -> Bool {
    guard isStarted else { return false }
    guard readerWindow.isVisible else { return false }
    guard !isRunning else { return false }
    return true
  }

  private func captureContext() -> CaptureContext? {
    guard let windowID = readerWindow.captureWindowID else { return nil }
    return CaptureContext(windowID: windowID, sourceRect: readerWindow.captureRectInScreen())
  }

  private func beginTask(taskID: UUID, operation: ReaderOperation, status: String, timeout: TimeInterval) {
    timeoutWorkItem?.cancel()
    currentTask?.cancel()
    currentTaskID = taskID
    currentOperation = operation
    isRunning = true
    readerWindow.viewModel.isBusy = true
    readerWindow.viewModel.canCancelAssist = operation == .assistCurrent || operation == .assistSession
    readerWindow.viewModel.lastError = nil
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

  private func clearCurrentReading() {
    currentSnapshot = nil
    readerWindow.viewModel.recognizedBlocks = []
    readerWindow.viewModel.recognizedText = ""
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = nil
    readerWindow.viewModel.lastSnapshotAt = nil
  }

  private func clearReadingSession() {
    readerWindow.viewModel.sessionChunks = []
    readerWindow.viewModel.sessionSnapshotCount = 0
    readerWindow.viewModel.sessionAssistantText = ""
    readerWindow.viewModel.sessionAssistantError = nil
    readerWindow.viewModel.sessionLastUpdatedAt = nil
  }

  private func clearSnapshotBuffer() {
    currentSnapshot = nil
    readingSession = nil
    readerWindow.viewModel.recognizedBlocks = []
    readerWindow.viewModel.recognizedText = ""
    readerWindow.viewModel.lastSnapshotAt = nil
    readerWindow.viewModel.sessionChunks = []
    readerWindow.viewModel.sessionSnapshotCount = 0
    readerWindow.viewModel.sessionLastUpdatedAt = nil
    readerWindow.viewModel.sessionAssistantText = ""
    readerWindow.viewModel.sessionAssistantError = nil
  }

  private func applySnapshot(_ snapshot: ReadingSnapshot, status: String) {
    currentSnapshot = snapshot
    readerWindow.viewModel.recognizedBlocks = snapshot.blocks
    readerWindow.viewModel.recognizedText = snapshot.plainText
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = nil
    readerWindow.viewModel.lastSnapshotAt = snapshot.capturedAt
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = status
  }

  private func appendSnapshotToReadingSession(_ snapshot: ReadingSnapshot) {
    let merge = Self.mergeSession(existing: readingSession, with: snapshot)
    readingSession = merge.session
    readerWindow.viewModel.sessionChunks = merge.session.chunks
    readerWindow.viewModel.sessionSnapshotCount = merge.session.snapshotCount
    readerWindow.viewModel.sessionAssistantText = ""
    readerWindow.viewModel.sessionAssistantError = nil
    readerWindow.viewModel.sessionLastUpdatedAt = merge.session.updatedAt
    readerWindow.viewModel.lastError = nil

    if merge.isNewSession {
      readerWindow.viewModel.statusText = "스냅샷 누적 시작"
    } else if merge.appendedLineCount > 0 {
      readerWindow.viewModel.statusText = "스냅샷 누적됨"
    } else {
      readerWindow.viewModel.statusText = "중복 구간만 감지됨"
    }
  }

  private func applyCurrentAssistantResult(_ result: AssistantResult) {
    readerWindow.viewModel.assistantText = result.outputText
    readerWindow.viewModel.assistantError = nil
    readerWindow.viewModel.lastAssistantAt = result.completedAt
    readerWindow.viewModel.sessionAssistantText = ""
    readerWindow.viewModel.sessionAssistantError = nil
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = "준비됨"
  }

  private func applySessionAssistantResult(_ result: AssistantResult) {
    readerWindow.viewModel.assistantText = result.outputText
    readerWindow.viewModel.assistantError = nil
    readerWindow.viewModel.lastAssistantAt = result.completedAt
    readerWindow.viewModel.lastError = nil
    readerWindow.viewModel.statusText = "도움 완료"
  }

  private func setCurrentAssistantUnavailable(_ message: String) {
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = message
    readerWindow.viewModel.sessionAssistantText = ""
    readerWindow.viewModel.sessionAssistantError = nil
    readerWindow.viewModel.lastError = message
    readerWindow.viewModel.statusText = "현재 도움 사용 불가"
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false
  }

  private func setSessionAssistantUnavailable(_ message: String) {
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = message
    readerWindow.viewModel.lastError = message
    readerWindow.viewModel.statusText = "도움 사용 불가"
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false
  }

  private func handlePermissionDenied(for operation: ReaderOperation) {
    permissionPrompter.requestScreenRecordingIfNeeded()
    readerWindow.viewModel.lastError = nil

    switch operation {
    case .read, .assistCurrent, .append:
      clearCurrentReading()
      readerWindow.viewModel.statusText = "권한 필요"
    case .assistSession:
      setSessionAssistantUnavailable("도움을 실행할 수 없습니다.")
    }
  }

  private func handlePipelineError(_ error: ReaderPipelineError) {
    let status = Self.statusText(for: error)
    readerWindow.viewModel.lastError = nil

    switch currentOperation {
    case .append:
      clearCurrentReading()
      readerWindow.viewModel.statusText = status
    case .assistCurrent, .read, .none:
      clearCurrentReading()
      readerWindow.viewModel.statusText = status
    case .assistSession:
      setSessionAssistantUnavailable(status)
    }
  }

  private func handleUnexpectedPipelineError(_ message: String) {
    let status = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "OCR 오류" : message
    readerWindow.viewModel.lastError = status

    switch currentOperation {
    case .append:
      clearCurrentReading()
      readerWindow.viewModel.statusText = status
    case .assistCurrent, .read, .none:
      clearCurrentReading()
      readerWindow.viewModel.statusText = status
    case .assistSession:
      setSessionAssistantUnavailable(status)
    }
  }

  private func startAssistantTask(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    command: String,
    kind: AssistantTaskKind
  ) -> Task<Void, Never> {
    let taskID = UUID()
    let assistantFactory = self.assistantProviderFactory
    let operation: ReaderOperation = kind == .current ? .assistCurrent : .assistSession
    let status = "도움 생성 중"

    beginTask(taskID: taskID, operation: operation, status: status, timeout: assistantPipelineTimeout)
    readerWindow.viewModel.assistantText = ""
    readerWindow.viewModel.assistantError = nil
    currentTask = Task.detached(priority: .userInitiated) { [weak self] in
      defer {
        Task { @MainActor [weak self] in
          self?.finishRun(taskID: taskID)
        }
      }

      guard let self else { return }

      do {
        let provider = assistantFactory(command)
        let result = try await provider.run(snapshot: snapshot, preset: preset) { event in
          Task { @MainActor [weak self] in
            self?.applyIfCurrent(taskID: taskID) {
              self?.applyAssistantEvent(event)
            }
          }
        }

        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            switch kind {
            case .current:
              self.applyCurrentAssistantResult(result)
            case .session:
              self.applySessionAssistantResult(result)
            }
          }
        }
      } catch is CancellationError {
        return
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await MainActor.run {
          self.applyIfCurrent(taskID: taskID) {
            switch kind {
            case .current:
              self.setCurrentAssistantUnavailable(message)
            case .session:
              self.setSessionAssistantUnavailable(message)
            }
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

    let message = "작업 시간이 초과되었습니다."
    currentTask?.cancel()
    currentTask = nil
    currentTaskID = nil
    timeoutWorkItem = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false
    readerWindow.viewModel.lastError = message
    readerWindow.viewModel.statusText = "시간 초과"

    switch currentOperation {
    case .assistSession:
      readerWindow.viewModel.assistantText = ""
      readerWindow.viewModel.assistantError = message
    case .assistCurrent:
      readerWindow.viewModel.assistantText = ""
      readerWindow.viewModel.assistantError = message
    case .read, .append, .none:
      break
    }

    currentOperation = nil
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
    currentOperation = nil
    isRunning = false
    readerWindow.viewModel.isBusy = false
    readerWindow.viewModel.canCancelAssist = false
  }

  private func applyAssistantEvent(_ event: AssistantStreamEvent) {
    switch event {
    case let .textDelta(delta):
      if readerWindow.viewModel.assistantText.isEmpty {
        readerWindow.viewModel.assistantText = delta
      } else {
        readerWindow.viewModel.assistantText += delta
      }
      readerWindow.viewModel.assistantError = nil
      readerWindow.viewModel.lastError = nil
    }
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

  nonisolated private static func mergeSession(
    existing: ReadingSession?,
    with snapshot: ReadingSnapshot
  ) -> SessionMergeOutcome {
    let incomingLines = sessionLines(from: snapshot.plainText)

    guard let existing else {
      let text = incomingLines.joined(separator: "\n")
      return SessionMergeOutcome(
        session: ReadingSession(
          createdAt: snapshot.capturedAt,
          updatedAt: snapshot.capturedAt,
          snapshotCount: 1,
          chunks: text.isEmpty ? [] : [ReadingChunk(text: text)],
          tailLines: incomingLines
        ),
        isNewSession: true,
        appendedLineCount: incomingLines.count
      )
    }

    let overlapCount = overlappingLineCount(
      existingLines: existing.tailLines,
      incomingLines: incomingLines,
      maxWindow: ReadingSession.overlapWindow
    )
    let appendedLines = Array(incomingLines.dropFirst(overlapCount))
    let tailLines = Array((existing.tailLines + appendedLines).suffix(ReadingSession.overlapWindow))
    let chunks = existing.chunks + appendedChunk(from: appendedLines)

    return SessionMergeOutcome(
      session: ReadingSession(
        id: existing.id,
        createdAt: existing.createdAt,
        updatedAt: snapshot.capturedAt,
        snapshotCount: existing.snapshotCount + 1,
        chunks: chunks,
        tailLines: tailLines
      ),
      isNewSession: false,
      appendedLineCount: appendedLines.count
    )
  }

  nonisolated private static func appendedChunk(from lines: [String]) -> [ReadingChunk] {
    let text = lines.joined(separator: "\n")
    guard !text.isEmpty else { return [] }
    return [ReadingChunk(text: text)]
  }

  nonisolated private static func sessionLines(from text: String) -> [String] {
    text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  nonisolated private static func overlappingLineCount(
    existingLines: [String],
    incomingLines: [String],
    maxWindow: Int = 12
  ) -> Int {
    let maxOverlap = min(existingLines.count, incomingLines.count, maxWindow)
    guard maxOverlap > 0 else { return 0 }

    for overlap in stride(from: maxOverlap, through: 1, by: -1) {
      let existingSlice = existingLines.suffix(overlap).map(normalizedLine)
      let incomingSlice = incomingLines.prefix(overlap).map(normalizedLine)
      if existingSlice.elementsEqual(incomingSlice) {
        return overlap
      }
    }

    return 0
  }

  nonisolated private static func normalizedLine(_ line: String) -> String {
    line
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .lowercased()
  }

  nonisolated private static func statusText(for error: ReaderPipelineError) -> String {
    switch error {
    case .noPermission:
      return "권한 필요"
    case .captureFailed:
      return "캡처 실패"
    case .noTextFound:
      return "텍스트 없음"
    case .ocrFailed:
      return "OCR 오류"
    }
  }

  nonisolated private static func rectsApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2.0) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
      abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
      abs(lhs.size.width - rhs.size.width) <= tolerance &&
      abs(lhs.size.height - rhs.size.height) <= tolerance
  }
}

private struct CaptureContext {
  let windowID: CGWindowID
  let sourceRect: CGRect
}

private struct SessionMergeOutcome {
  let session: ReadingSession
  let isNewSession: Bool
  let appendedLineCount: Int
}

private enum ReaderOperation {
  case read
  case append
  case assistCurrent
  case assistSession
}

private enum AssistantTaskKind {
  case current
  case session
}

private enum ReaderPipelineError: Error {
  case noPermission
  case captureFailed
  case noTextFound
  case ocrFailed
}

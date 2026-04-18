import CoreGraphics
import Foundation
import Testing
@testable import SpectraReaderBase

struct ReaderCoordinatorTests {
  @Test
  @MainActor
  func snapshotAccumulatesBufferAndDropsOverlappingLines() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blockSequences: [
      [
        TextBlock(text: "첫 줄", boundingBox: CGRect(x: 0, y: 0.3, width: 0.4, height: 0.1)),
        TextBlock(text: "둘째 줄", boundingBox: CGRect(x: 0, y: 0.2, width: 0.4, height: 0.1)),
        TextBlock(text: "셋째 줄", boundingBox: CGRect(x: 0, y: 0.1, width: 0.4, height: 0.1))
      ],
      [
        TextBlock(text: "둘째 줄", boundingBox: CGRect(x: 0, y: 0.3, width: 0.4, height: 0.1)),
        TextBlock(text: "셋째 줄", boundingBox: CGRect(x: 0, y: 0.2, width: 0.4, height: 0.1)),
        TextBlock(text: "넷째 줄", boundingBox: CGRect(x: 0, y: 0.1, width: 0.4, height: 0.1))
      ]
    ])
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in MockAssistantProvider(resultText: "") },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value
    await coordinator.readNow()?.value

    #expect(capture.captureCount == 2)
    #expect(ocr.recognitionCount == 2)
    #expect(bufferedText(in: window.viewModel) == "첫 줄\n둘째 줄\n셋째 줄\n넷째 줄")
    #expect(window.viewModel.sessionChunks.count == 2)
    #expect(window.viewModel.sessionSnapshotCount == 2)
    #expect(window.viewModel.statusText == "스냅샷 누적됨")
  }

  @Test
  @MainActor
  func assistUsesBufferedSnapshotsAndKeepsBufferOnSuccess() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [
      TextBlock(text: "Hello world", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
    ])
    let assistant = MockAssistantProvider(resultText: "요약 결과")
    let authorizer = MockScreenCaptureAuthorizer(isAllowed: true)
    let settings = SettingsStore(defaults: makeDefaults())
    settings.helperCommandPath = "/usr/bin/helper"

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in assistant },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: authorizer,
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value
    await coordinator.assistNow()?.value

    #expect(capture.captureCount == 1)
    #expect(ocr.recognitionCount == 1)
    #expect(assistant.runCount == 1)
    #expect(assistant.lastSnapshotText == "Hello world")
    #expect(window.viewModel.assistantText == "요약 결과")
    #expect(window.viewModel.assistantError == nil)
    #expect(bufferedText(in: window.viewModel) == "Hello world")
    #expect(window.viewModel.sessionSnapshotCount == 1)
    #expect(window.viewModel.recognizedText == "Hello world")
    #expect(window.viewModel.statusText == "도움 완료")
  }

  @Test
  @MainActor
  func cancelAssistKeepsBufferedSnapshots() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [
      TextBlock(text: "누적 원문", boundingBox: CGRect(x: 0, y: 0, width: 0.4, height: 0.1))
    ])
    let assistant = MockAssistantProvider(delayNanoseconds: 2_000_000_000, resultText: "늦은 응답")
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in assistant },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value
    let task = coordinator.assistNow()
    #expect(coordinator.cancelAssistIfRunning() == true)
    await task?.value

    #expect(window.viewModel.statusText == "도움 취소됨")
    #expect(bufferedText(in: window.viewModel) == "누적 원문")
    #expect(window.viewModel.assistantText.isEmpty)
  }

  @Test
  @MainActor
  func assistWithoutSnapshotShowsUnavailableWithoutCapturing() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let assistant = MockAssistantProvider(resultText: "unused")
    let settings = SettingsStore(defaults: makeDefaults())
    settings.helperCommandPath = "/usr/bin/helper"

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: MockOCRService(blocks: []),
      assistantProviderFactory: { _ in assistant },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    let task = coordinator.assistNow()
    await task?.value

    #expect(capture.captureCount == 0)
    #expect(assistant.runCount == 0)
    #expect(window.viewModel.statusText == "도움 사용 불가")
    #expect(window.viewModel.assistantError == "먼저 '스냅샷'으로 원문을 쌓으세요.")
  }

  @Test
  @MainActor
  func helperFailureKeepsBufferedSnapshots() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [
      TextBlock(text: "Some text", boundingBox: CGRect(x: 0, y: 0, width: 0.4, height: 0.1))
    ])
    let assistant = MockAssistantProvider(error: AssistantError.codexUnavailable)
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in assistant },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value
    await coordinator.assistNow()?.value

    #expect(window.viewModel.statusText == "도움 사용 불가")
    #expect(window.viewModel.lastError == "Codex CLI를 찾을 수 없습니다.")
    #expect(window.viewModel.assistantError == "Codex CLI를 찾을 수 없습니다.")
    #expect(bufferedText(in: window.viewModel) == "Some text")
    #expect(window.viewModel.sessionSnapshotCount == 1)
  }

  @Test
  @MainActor
  func resetReadingSessionClearsBufferedSnapshotState() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [
      TextBlock(text: "현재 화면", boundingBox: CGRect(x: 0, y: 0, width: 0.4, height: 0.12))
    ])
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in MockAssistantProvider(resultText: "") },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value
    coordinator.resetReadingSession()

    #expect(window.viewModel.sessionChunks.isEmpty)
    #expect(window.viewModel.sessionSnapshotCount == 0)
    #expect(window.viewModel.recognizedText.isEmpty)
    #expect(window.viewModel.statusText == "스냅샷 비움")
  }

  @Test
  @MainActor
  func noPermissionStopsBeforeCapture() {
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: Self.makeTestImage())
    let ocr = MockOCRService(blocks: [TextBlock(text: "Hidden", boundingBox: CGRect(x: 0, y: 0, width: 0.3, height: 0.1))])
    let prompter = MockPermissionPrompter()
    let authorizer = MockScreenCaptureAuthorizer(isAllowed: false)
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in MockAssistantProvider(resultText: "") },
      permissionPrompter: prompter,
      screenCaptureAuthorizer: authorizer,
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    let task = coordinator.readNow()

    #expect(task == nil)
    #expect(capture.captureCount == 0)
    #expect(prompter.requestCount == 1)
    #expect(window.viewModel.statusText == "권한 필요")
  }

  @Test
  @MainActor
  func noTextFoundOnSnapshotShowsEmptyStatus() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [])
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in MockAssistantProvider(resultText: "") },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value

    #expect(window.viewModel.statusText == "텍스트 없음")
    #expect(window.viewModel.sessionChunks.isEmpty)
    #expect(window.viewModel.assistantText.isEmpty)
  }

  @Test
  @MainActor
  func localizedOCRErrorIsShownAsStatus() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(error: MockLocalizedOCRError())
    let settings = SettingsStore(defaults: makeDefaults())

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in MockAssistantProvider(resultText: "") },
      permissionPrompter: MockPermissionPrompter(),
      screenCaptureAuthorizer: MockScreenCaptureAuthorizer(isAllowed: true),
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    await coordinator.readNow()?.value

    #expect(window.viewModel.statusText == "OCR 서비스를 사용할 수 없습니다.")
    #expect(window.viewModel.lastError == "OCR 서비스를 사용할 수 없습니다.")
  }

  @MainActor
  private func makeDefaults() -> UserDefaults {
    let suiteName = "ReaderCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func bufferedText(in viewModel: ReaderViewModel) -> String {
    viewModel.sessionChunks.map(\.text).joined(separator: "\n")
  }

  private static func makeTestImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 2 * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    )!
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    return context.makeImage()!
  }
}

@MainActor
private final class MockReaderWindow: ReaderWindowing {
  let viewModel = ReaderViewModel()
  var isVisible = true
  var captureWindowID: CGWindowID? = 42
  var sourceRect = CGRect(x: 0, y: 0, width: 400, height: 240)

  func captureRectInScreen() -> CGRect {
    sourceRect
  }
}

private final class MockCaptureService: @unchecked Sendable, ScreenCapturing {
  private let lock = NSLock()
  private let image: CGImage?
  private(set) var captureCount = 0

  init(image: CGImage?) {
    self.image = image
  }

  func capture(rect: CGRect, below windowID: CGWindowID) -> CGImage? {
    lock.withLock {
      captureCount += 1
    }
    return image
  }
}

private final class MockOCRService: @unchecked Sendable, OCRRecognizing {
  private let lock = NSLock()
  private let blockSequences: [[TextBlock]]
  private let error: Error?
  private(set) var recognitionCount = 0

  init(blocks: [TextBlock]) {
    self.blockSequences = [blocks]
    self.error = nil
  }

  init(blockSequences: [[TextBlock]]) {
    self.blockSequences = blockSequences
    self.error = nil
  }

  init(error: Error) {
    self.blockSequences = [[]]
    self.error = error
  }

  func recognizeTextBlocks(in cgImage: CGImage) throws -> [TextBlock] {
    let currentCount = lock.withLock {
      recognitionCount += 1
      return recognitionCount
    }
    if let error {
      throw error
    }
    let index = min(max(0, currentCount - 1), blockSequences.count - 1)
    return blockSequences[index]
  }
}

private final class MockAssistantProvider: @unchecked Sendable, AssistantProviding {
  private let lock = NSLock()
  private let delayNanoseconds: UInt64
  private let resultText: String?
  private let error: Error?
  private(set) var runCount = 0
  private(set) var lastSnapshotText: String?

  init(delayNanoseconds: UInt64 = 0, resultText: String? = nil, error: Error? = nil) {
    self.delayNanoseconds = delayNanoseconds
    self.resultText = resultText
    self.error = error
  }

  func run(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    onEvent: @escaping @Sendable (AssistantStreamEvent) -> Void
  ) async throws -> AssistantResult {
    lock.withLock {
      runCount += 1
      lastSnapshotText = snapshot.plainText
    }

    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    if let error {
      throw error
    }

    if let resultText, !resultText.isEmpty {
      onEvent(.textDelta(resultText))
    }

    return AssistantResult(
      presetID: preset.id,
      snapshotID: snapshot.id,
      outputText: resultText ?? ""
    )
  }
}

@MainActor
private final class MockPermissionPrompter: ScreenRecordingPrompting {
  private(set) var requestCount = 0

  func requestScreenRecordingIfNeeded() {
    requestCount += 1
  }
}

private struct MockScreenCaptureAuthorizer: ScreenCaptureAuthorizing {
  let isAllowed: Bool

  func hasAccess() -> Bool {
    isAllowed
  }
}

private struct MockLocalizedOCRError: LocalizedError {
  var errorDescription: String? {
    "OCR 서비스를 사용할 수 없습니다."
  }
}

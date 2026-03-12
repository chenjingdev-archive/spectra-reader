import CoreGraphics
import Foundation
import Testing
@testable import SpectraReaderBase

struct ReaderCoordinatorTests {
  @Test
  @MainActor
  func assistReusesRecentSnapshotWithoutCapturingAgain() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [TextBlock(text: "Hello world", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))])
    let assistant = MockAssistantProvider(resultText: "요약 결과")
    let authorizer = MockScreenCaptureAuthorizer(isAllowed: true)
    let prompter = MockPermissionPrompter()
    let settings = SettingsStore(defaults: makeDefaults())
    settings.helperCommandPath = "/usr/bin/helper"

    let coordinator = ReaderCoordinator(
      settings: settings,
      readerWindow: window,
      captureService: capture,
      ocrService: ocr,
      assistantProviderFactory: { _ in assistant },
      permissionPrompter: prompter,
      screenCaptureAuthorizer: authorizer,
      pipelineTimeout: 5
    )

    coordinator.startIfNeeded()
    let readTask = coordinator.readNow()
    await readTask?.value

    #expect(capture.captureCount == 1)
    #expect(ocr.recognitionCount == 1)
    #expect(window.viewModel.recognizedText == "Hello world")

    let assistTask = coordinator.assistNow()
    await assistTask?.value

    #expect(capture.captureCount == 1)
    #expect(ocr.recognitionCount == 1)
    #expect(assistant.runCount == 1)
    #expect(window.viewModel.assistantText == "요약 결과")
    #expect(window.viewModel.statusText == "준비됨")
  }

  @Test
  @MainActor
  func assistWithoutSnapshotCapturesThenRunsAssistant() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [TextBlock(text: "Action item", boundingBox: CGRect(x: 0, y: 0, width: 0.4, height: 0.12))])
    let assistant = MockAssistantProvider(resultText: "지금 해야 할 일")
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
    let task = coordinator.assistNow()
    await task?.value

    #expect(capture.captureCount == 1)
    #expect(ocr.recognitionCount == 1)
    #expect(assistant.runCount == 1)
    #expect(window.viewModel.recognizedText == "Action item")
    #expect(window.viewModel.assistantText == "지금 해야 할 일")
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
  func noTextFoundSkipsAssistant() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [])
    let assistant = MockAssistantProvider(resultText: "unused")
    let settings = SettingsStore(defaults: makeDefaults())
    settings.helperCommandPath = "/usr/bin/helper"

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
    let task = coordinator.assistNow()
    await task?.value

    #expect(assistant.runCount == 0)
    #expect(window.viewModel.statusText == "텍스트 없음")
    #expect(window.viewModel.recognizedText.isEmpty)
  }

  @Test
  @MainActor
  func helperFailureShowsAssistantUnavailable() async {
    let image = Self.makeTestImage()
    let window = MockReaderWindow()
    let capture = MockCaptureService(image: image)
    let ocr = MockOCRService(blocks: [TextBlock(text: "Some text", boundingBox: CGRect(x: 0, y: 0, width: 0.4, height: 0.1))])
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
    let task = coordinator.assistNow()
    await task?.value

    #expect(window.viewModel.statusText == "도움 사용 불가")
    #expect(window.viewModel.lastError == "Codex CLI를 찾을 수 없습니다.")
    #expect(window.viewModel.recognizedText == "Some text")
  }

  @MainActor
  private func makeDefaults() -> UserDefaults {
    let suiteName = "ReaderCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
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
  private let blocks: [TextBlock]
  private(set) var recognitionCount = 0

  init(blocks: [TextBlock]) {
    self.blocks = blocks
  }

  func recognizeTextBlocks(in cgImage: CGImage) throws -> [TextBlock] {
    lock.withLock {
      recognitionCount += 1
    }
    return blocks
  }
}

private final class MockAssistantProvider: @unchecked Sendable, AssistantProviding {
  private let lock = NSLock()
  private let resultText: String?
  private let error: Error?
  private(set) var runCount = 0

  init(resultText: String? = nil, error: Error? = nil) {
    self.resultText = resultText
    self.error = error
  }

  func run(snapshot: ReadingSnapshot, preset: AssistPreset) async throws -> AssistantResult {
    lock.withLock {
      runCount += 1
    }

    if let error {
      throw error
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

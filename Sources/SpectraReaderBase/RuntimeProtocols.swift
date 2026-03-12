import Foundation
import CoreGraphics

@MainActor
protocol ReaderWindowing: AnyObject {
  var viewModel: ReaderViewModel { get }
  var isVisible: Bool { get }
  var captureWindowID: CGWindowID? { get }

  func captureRectInScreen() -> CGRect
}

protocol ScreenCapturing: Sendable {
  func capture(rect: CGRect, below windowID: CGWindowID) -> CGImage?
}

protocol OCRRecognizing: Sendable {
  func recognizeTextBlocks(in cgImage: CGImage) throws -> [TextBlock]
}

@MainActor
protocol ScreenRecordingPrompting {
  func requestScreenRecordingIfNeeded()
}

protocol ScreenCaptureAuthorizing: Sendable {
  func hasAccess() -> Bool
}

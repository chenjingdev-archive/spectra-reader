import AppKit
import CoreGraphics

struct ScreenCaptureService: ScreenCapturing {
  func capture(rect: CGRect, below windowID: CGWindowID) -> CGImage? {
    CGWindowListCreateImage(
      rect,
      .optionOnScreenBelowWindow,
      windowID,
      [.boundsIgnoreFraming, .bestResolution]
    )
  }

  static func requestAccessIfNeeded() {
    if !CGPreflightScreenCaptureAccess() {
      CGRequestScreenCaptureAccess()
    }
  }
}

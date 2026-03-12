import CoreGraphics

struct ScreenCaptureAuthorization: ScreenCaptureAuthorizing {
  func hasAccess() -> Bool {
    CGPreflightScreenCaptureAccess()
  }
}

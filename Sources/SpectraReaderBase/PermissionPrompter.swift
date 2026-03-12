import AppKit

@MainActor
final class PermissionPrompter: ScreenRecordingPrompting {
  static let shared = PermissionPrompter()
  private var hasRequestedScreenRecordingThisRun = false
  private var hasRequestedAccessibilityThisRun = false

  func requestScreenRecordingIfNeeded() {
    if CGPreflightScreenCaptureAccess() {
      hasRequestedScreenRecordingThisRun = false
      return
    }

    guard !hasRequestedScreenRecordingThisRun else { return }

    hasRequestedScreenRecordingThisRun = true
    ScreenCaptureService.requestAccessIfNeeded()
  }

  func requestAccessibilityForHotkeysIfNeeded() {
    if AccessibilityPermission.isTrusted() {
      hasRequestedAccessibilityThisRun = false
      return
    }

    guard !hasRequestedAccessibilityThisRun else { return }
    hasRequestedAccessibilityThisRun = true
    AccessibilityPermission.requestIfNeeded()
  }
}

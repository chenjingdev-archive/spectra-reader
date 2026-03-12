import ApplicationServices

@MainActor
enum AccessibilityPermission {
  static func isTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  static func requestIfNeeded() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}

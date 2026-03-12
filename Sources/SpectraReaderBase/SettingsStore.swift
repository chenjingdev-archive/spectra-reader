import Foundation
import CoreGraphics
import Combine
import AppKit
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
  @Published var intervalSeconds: Double {
    didSet { saveInterval() }
  }

  @Published var intervalEnabled: Bool {
    didSet { saveIntervalEnabled() }
  }

  @Published var readerEnabled: Bool {
    didSet { saveReaderEnabled() }
  }

  @Published var lensOpacity: Double {
    didSet { saveLensOpacity() }
  }

  @Published var lensFrame: CGRect? {
    didSet { saveLensFrame() }
  }

  @Published var fontSizeOffset: Double {
    didSet { saveFontSizeOffset() }
  }

  @Published var letterSpacing: Double {
    didSet { saveLetterSpacing() }
  }

  @Published var hotkeyModifiers: UInt {
    didSet { saveHotkey() }
  }

  @Published var hotkeyKeyCode: Int {
    didSet { saveHotkey() }
  }

  @Published var textColorHex: String {
    didSet { saveTextColor() }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let storedInterval = defaults.object(forKey: Keys.intervalSeconds) as? Double
    intervalSeconds = max(1.0, storedInterval ?? 2.0)
    intervalEnabled = defaults.bool(forKey: Keys.intervalEnabled)

    if defaults.object(forKey: Keys.readerEnabled) == nil {
      readerEnabled = true
    } else {
      readerEnabled = defaults.bool(forKey: Keys.readerEnabled)
    }

    let storedOpacity = defaults.object(forKey: Keys.lensOpacity) as? Double
    lensOpacity = min(0.9, max(0.05, storedOpacity ?? 0.55))

    lensFrame = Self.loadLensFrame(from: defaults)

    let storedOffset = defaults.object(forKey: Keys.fontSizeOffset) as? Double
    fontSizeOffset = storedOffset ?? 2.0

    let storedTracking = defaults.object(forKey: Keys.letterSpacing) as? Double
    letterSpacing = storedTracking ?? 1.2

    let storedHotkeyModifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt
    let storedHotkeyKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
    hotkeyModifiers = storedHotkeyModifiers ?? 0
    hotkeyKeyCode = storedHotkeyKeyCode ?? -1

    textColorHex = defaults.string(forKey: Keys.textColorHex) ?? "#FFFFFF"
  }

  private enum Keys {
    static let intervalSeconds = "intervalSeconds"
    static let intervalEnabled = "intervalEnabled"
    static let readerEnabled = "readerEnabled"
    static let lensOpacity = "lensOpacity"
    static let lensFrame = "lensFrame"
    static let fontSizeOffset = "fontSizeOffset"
    static let letterSpacing = "letterSpacing"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let textColorHex = "textColorHex"
  }

  private func saveTextColor() {
    defaults.set(textColorHex, forKey: Keys.textColorHex)
  }

  private func saveHotkey() {
    defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
    defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
  }

  private func saveInterval() {
    defaults.set(intervalSeconds, forKey: Keys.intervalSeconds)
  }

  private func saveFontSizeOffset() {
    defaults.set(fontSizeOffset, forKey: Keys.fontSizeOffset)
  }

  private func saveLetterSpacing() {
    defaults.set(letterSpacing, forKey: Keys.letterSpacing)
  }

  private func saveIntervalEnabled() {
    defaults.set(intervalEnabled, forKey: Keys.intervalEnabled)
  }

  private func saveReaderEnabled() {
    defaults.set(readerEnabled, forKey: Keys.readerEnabled)
  }

  private func saveLensOpacity() {
    defaults.set(lensOpacity, forKey: Keys.lensOpacity)
  }

  private func saveLensFrame() {
    guard let frame = lensFrame else {
      defaults.removeObject(forKey: Keys.lensFrame)
      return
    }

    let payload: [String: Double] = [
      "x": frame.origin.x,
      "y": frame.origin.y,
      "w": frame.size.width,
      "h": frame.size.height
    ]
    defaults.set(payload, forKey: Keys.lensFrame)
  }

  private static func loadLensFrame(from defaults: UserDefaults) -> CGRect? {
    guard let payload = defaults.dictionary(forKey: Keys.lensFrame) as? [String: Double],
          let x = payload["x"],
          let y = payload["y"],
          let w = payload["w"],
          let h = payload["h"]
    else {
      return nil
    }

    return CGRect(x: x, y: y, width: w, height: h)
  }
}

extension SettingsStore {
  var textColorBinding: Binding<Color> {
    Binding(
      get: { Color(hex: self.textColorHex) },
      set: { self.textColorHex = $0.toHex() ?? "#FFFFFF" }
    )
  }
}

extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3:
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (255, 1, 1, 1)
    }

    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: Double(a) / 255
    )
  }

  func toHex() -> String? {
    guard let srgbColor = NSColor(self).usingColorSpace(.sRGB),
          let components = srgbColor.cgColor.components,
          components.count >= 3
    else {
      return nil
    }

    let r = components[0]
    let g = components[1]
    let b = components[2]

    return String(format: "#%02lX%02lX%02lX", lround(r * 255), lround(g * 255), lround(b * 255))
  }
}

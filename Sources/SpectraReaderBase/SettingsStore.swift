import Foundation
import CoreGraphics
import Combine

@MainActor
final class SettingsStore: ObservableObject {
  @Published var lensFrame: CGRect? {
    didSet { saveLensFrame() }
  }

  @Published var assistantFrame: CGRect? {
    didSet { saveAssistantFrame() }
  }

  @Published var overlayOpacity: Double {
    didSet { defaults.set(overlayOpacity, forKey: Keys.overlayOpacity) }
  }

  @Published var allowsClickThrough: Bool {
    didSet { defaults.set(allowsClickThrough, forKey: Keys.allowsClickThrough) }
  }

  @Published var hidesOverlayText: Bool {
    didSet { defaults.set(hidesOverlayText, forKey: Keys.hidesOverlayText) }
  }

  @Published var toggleHotkey: HotkeyBinding {
    didSet { saveHotkey(toggleHotkey, prefix: Keys.toggleHotkey) }
  }

  @Published var assistHotkey: HotkeyBinding {
    didSet { saveHotkey(assistHotkey, prefix: Keys.assistHotkey) }
  }

  @Published var helperCommandPath: String {
    didSet { defaults.set(helperCommandPath, forKey: Keys.helperCommandPath) }
  }

  @Published var selectedPresetID: String {
    didSet {
      defaults.set(selectedPresetID, forKey: Keys.selectedPresetID)
      reconcileSelectedPreset()
    }
  }

  @Published var presets: [AssistPreset] {
    didSet {
      savePresets()
      reconcileSelectedPreset()
    }
  }

  private let defaults: UserDefaults
  private var isReconcilingPresetSelection = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedPresets = Self.loadPresets(from: defaults)
    let initialPresets = storedPresets.isEmpty ? AssistPreset.defaultPresets() : storedPresets

    lensFrame = Self.loadLensFrame(from: defaults)
    assistantFrame = Self.loadFrame(forKey: Keys.assistantFrame, from: defaults)
    overlayOpacity = Self.loadOverlayOpacity(from: defaults)
    allowsClickThrough = defaults.bool(forKey: Keys.allowsClickThrough)
    hidesOverlayText = defaults.bool(forKey: Keys.hidesOverlayText)
    toggleHotkey = Self.loadHotkey(from: defaults, prefix: Keys.toggleHotkey) ?? Self.loadLegacyToggleHotkey(from: defaults)
    assistHotkey = Self.loadHotkey(from: defaults, prefix: Keys.assistHotkey) ?? .none
    helperCommandPath = defaults.string(forKey: Keys.helperCommandPath) ?? ""
    presets = initialPresets
    selectedPresetID = defaults.string(forKey: Keys.selectedPresetID) ?? initialPresets.first?.id ?? ""
    reconcileSelectedPreset()
  }

  var selectedPreset: AssistPreset? {
    presets.first { $0.id == selectedPresetID }
  }

  func addPreset() {
    let preset = AssistPreset(
      name: "새 프리셋",
      promptTemplate: "다음 화면 내용을 읽기 쉽게 설명해줘.",
      isBuiltIn: false
    )
    presets.append(preset)
    selectedPresetID = preset.id
  }

  func removeSelectedPreset() {
    guard let preset = selectedPreset, !preset.isBuiltIn else { return }
    presets.removeAll { $0.id == preset.id }
  }

  func updateSelectedPresetName(_ name: String) {
    updateSelectedPreset { $0.name = name }
  }

  func updateSelectedPresetPrompt(_ prompt: String) {
    updateSelectedPreset { $0.promptTemplate = prompt }
  }

  private enum Keys {
    static let lensFrame = "lensFrame"
    static let assistantFrame = "assistantFrame"
    static let overlayOpacity = "overlayOpacity"
    static let allowsClickThrough = "allowsClickThrough"
    static let hidesOverlayText = "hidesOverlayText"
    static let toggleHotkey = "toggleHotkey"
    static let assistHotkey = "assistHotkey"
    static let helperCommandPath = "helperCommandPath"
    static let selectedPresetID = "selectedPresetID"
    static let presets = "presets"
    static let legacyHotkeyModifiers = "hotkeyModifiers"
    static let legacyHotkeyKeyCode = "hotkeyKeyCode"
  }

  private func updateSelectedPreset(_ update: (inout AssistPreset) -> Void) {
    guard let index = presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
    var preset = presets[index]
    update(&preset)
    presets[index] = preset
  }

  private func reconcileSelectedPreset() {
    guard !isReconcilingPresetSelection else { return }
    isReconcilingPresetSelection = true
    defer { isReconcilingPresetSelection = false }

    if presets.isEmpty {
      presets = AssistPreset.defaultPresets()
    }

    if !presets.contains(where: { $0.id == selectedPresetID }), let firstPreset = presets.first {
      selectedPresetID = firstPreset.id
    }
  }

  private func saveHotkey(_ hotkey: HotkeyBinding, prefix: String) {
    defaults.set(hotkey.modifiers, forKey: "\(prefix).modifiers")
    defaults.set(hotkey.keyCode, forKey: "\(prefix).keyCode")
  }

  private func savePresets() {
    let data = try? JSONEncoder().encode(presets)
    defaults.set(data, forKey: Keys.presets)
  }

  private func saveLensFrame() {
    saveFrame(lensFrame, forKey: Keys.lensFrame)
  }

  private func saveAssistantFrame() {
    saveFrame(assistantFrame, forKey: Keys.assistantFrame)
  }

  private func saveFrame(_ frame: CGRect?, forKey key: String) {
    guard let frame else {
      defaults.removeObject(forKey: key)
      return
    }

    let payload: [String: Double] = [
      "x": frame.origin.x,
      "y": frame.origin.y,
      "w": frame.size.width,
      "h": frame.size.height
    ]
    defaults.set(payload, forKey: key)
  }

  private static func loadHotkey(from defaults: UserDefaults, prefix: String) -> HotkeyBinding? {
    let modifiersKey = "\(prefix).modifiers"
    let keyCodeKey = "\(prefix).keyCode"
    guard defaults.object(forKey: modifiersKey) != nil || defaults.object(forKey: keyCodeKey) != nil else {
      return nil
    }

    let modifiers = defaults.object(forKey: modifiersKey) as? UInt ?? 0
    let keyCode = defaults.object(forKey: keyCodeKey) as? Int ?? -1
    return HotkeyBinding(modifiers: modifiers, keyCode: keyCode)
  }

  private static func loadLegacyToggleHotkey(from defaults: UserDefaults) -> HotkeyBinding {
    let modifiers = defaults.object(forKey: Keys.legacyHotkeyModifiers) as? UInt ?? 0
    let keyCode = defaults.object(forKey: Keys.legacyHotkeyKeyCode) as? Int ?? -1
    return HotkeyBinding(modifiers: modifiers, keyCode: keyCode)
  }

  private static func loadPresets(from defaults: UserDefaults) -> [AssistPreset] {
    guard let data = defaults.data(forKey: Keys.presets),
          let presets = try? JSONDecoder().decode([AssistPreset].self, from: data)
    else {
      return []
    }

    return presets
  }

  private static func loadLensFrame(from defaults: UserDefaults) -> CGRect? {
    loadFrame(forKey: Keys.lensFrame, from: defaults)
  }

  private static func loadOverlayOpacity(from defaults: UserDefaults) -> Double {
    guard defaults.object(forKey: Keys.overlayOpacity) != nil else {
      return 0.76
    }

    return min(max(defaults.double(forKey: Keys.overlayOpacity), 0), 1)
  }

  private static func loadFrame(forKey key: String, from defaults: UserDefaults) -> CGRect? {
    guard let payload = defaults.dictionary(forKey: key) as? [String: Double],
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

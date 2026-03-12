import Foundation
import Testing
@testable import SpectraReaderBase

struct SettingsStoreTests {
  @Test
  @MainActor
  func presetsAndSelectionPersistAcrossReload() {
    let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = SettingsStore(defaults: defaults)
    store.overlayOpacity = 0.42
    store.allowsClickThrough = true
    store.hidesOverlayText = true
    store.helperCommandPath = "/tmp/helper"
    store.assistHotkey = HotkeyBinding(modifiers: UInt(1 << 20), keyCode: 36)
    store.addPreset()
    store.updateSelectedPresetName("커스텀")
    store.updateSelectedPresetPrompt("이 화면을 천천히 설명해줘.")
    let selectedID = store.selectedPresetID

    let reloaded = SettingsStore(defaults: defaults)

    #expect(reloaded.overlayOpacity == 0.42)
    #expect(reloaded.allowsClickThrough == true)
    #expect(reloaded.hidesOverlayText == true)
    #expect(reloaded.helperCommandPath == "/tmp/helper")
    #expect(reloaded.assistHotkey == HotkeyBinding(modifiers: UInt(1 << 20), keyCode: 36))
    #expect(reloaded.selectedPresetID == selectedID)
    #expect(reloaded.selectedPreset?.name == "커스텀")
    #expect(reloaded.selectedPreset?.promptTemplate == "이 화면을 천천히 설명해줘.")
  }
}

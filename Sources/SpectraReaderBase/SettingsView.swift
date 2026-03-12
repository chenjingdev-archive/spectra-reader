import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: SettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Color.clear.frame(height: 0).focusable()

        Text("리더 설정")
          .font(.title3)

        GroupBox(label: Text("오버레이")) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("투명도")
                .frame(width: 90, alignment: .leading)

              Slider(value: $settings.overlayOpacity, in: 0...1)

              Text("\(Int(settings.overlayOpacity * 100))%")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .trailing)
            }

            Toggle("배경 클릭 통과", isOn: $settings.allowsClickThrough)

            if settings.allowsClickThrough {
              Text("클릭 통과가 켜지면 오버레이 창을 직접 이동하거나 크기를 조절할 수 없습니다.")
                .font(.footnote)
                .foregroundColor(.secondary)
            }

            Toggle("OCR 오버레이 텍스트 숨기기", isOn: $settings.hidesOverlayText)
          }
          .padding(8)
        }

        GroupBox(label: Text("Codex 연결")) {
          VStack(alignment: .leading, spacing: 10) {
            TextField("고급: 외부 헬퍼 명령어", text: $settings.helperCommandPath)
              .textFieldStyle(.roundedBorder)

            Text("비워두면 설치된 `codex` CLI를 직접 사용합니다. 이 입력칸은 정말 다른 헬퍼를 붙일 때만 사용하세요.")
              .font(.footnote)
              .foregroundColor(.secondary)
          }
          .padding(8)
        }

        GroupBox(label: Text("프리셋")) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Picker("현재 프리셋", selection: $settings.selectedPresetID) {
                ForEach(settings.presets) { preset in
                  Text(preset.name).tag(preset.id)
                }
              }
              .pickerStyle(.menu)

              Spacer()

              Button("추가") {
                settings.addPreset()
              }

              Button("삭제") {
                settings.removeSelectedPreset()
              }
              .disabled(settings.selectedPreset?.isBuiltIn ?? true)
            }

            TextField("프리셋 이름", text: selectedPresetName)
              .textFieldStyle(.roundedBorder)

            TextEditor(text: selectedPresetPrompt)
              .font(.system(size: 13))
              .frame(minHeight: 130)
              .padding(6)
              .background(Color(nsColor: .textBackgroundColor))
              .clipShape(RoundedRectangle(cornerRadius: 8))

            if let preset = settings.selectedPreset {
              Text(preset.isBuiltIn ? "기본 프리셋" : "사용자 프리셋")
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
          .padding(8)
        }

        GroupBox(label: Text("단축키")) {
          VStack(alignment: .leading, spacing: 12) {
            hotkeyRow(
              title: "오버레이 표시/숨기기",
              modifiers: toggleHotkeyModifiers,
              keyCode: toggleHotkeyKeyCode
            )

            hotkeyRow(
              title: "현재 프리셋 도움 실행",
              modifiers: assistHotkeyModifiers,
              keyCode: assistHotkeyKeyCode
            )
          }
          .padding(8)
        }
      }
      .padding(18)
    }
    .frame(width: 460)
  }
}

private extension SettingsView {
  var selectedPresetName: Binding<String> {
    Binding(
      get: { settings.selectedPreset?.name ?? "" },
      set: { settings.updateSelectedPresetName($0) }
    )
  }

  var selectedPresetPrompt: Binding<String> {
    Binding(
      get: { settings.selectedPreset?.promptTemplate ?? "" },
      set: { settings.updateSelectedPresetPrompt($0) }
    )
  }

  var toggleHotkeyModifiers: Binding<UInt> {
    Binding(
      get: { settings.toggleHotkey.modifiers },
      set: {
        var hotkey = settings.toggleHotkey
        hotkey.modifiers = $0
        settings.toggleHotkey = hotkey
      }
    )
  }

  var toggleHotkeyKeyCode: Binding<Int> {
    Binding(
      get: { settings.toggleHotkey.keyCode },
      set: {
        var hotkey = settings.toggleHotkey
        hotkey.keyCode = $0
        settings.toggleHotkey = hotkey
      }
    )
  }

  var assistHotkeyModifiers: Binding<UInt> {
    Binding(
      get: { settings.assistHotkey.modifiers },
      set: {
        var hotkey = settings.assistHotkey
        hotkey.modifiers = $0
        settings.assistHotkey = hotkey
      }
    )
  }

  var assistHotkeyKeyCode: Binding<Int> {
    Binding(
      get: { settings.assistHotkey.keyCode },
      set: {
        var hotkey = settings.assistHotkey
        hotkey.keyCode = $0
        settings.assistHotkey = hotkey
      }
    )
  }

  func hotkeyRow(title: String, modifiers: Binding<UInt>, keyCode: Binding<Int>) -> some View {
    HStack {
      Text(title)
        .frame(width: 140, alignment: .leading)
      HotkeyRecorder(modifiers: modifiers, keyCode: keyCode)
      Spacer()
    }
  }
}

struct HotkeyRecorder: View {
  @Binding var modifiers: UInt
  @Binding var keyCode: Int
  @State private var isRecording = false
  @State private var pressedModifiers: NSEvent.ModifierFlags = []
  @State private var maxModifiers: NSEvent.ModifierFlags = []
  @State private var eventMonitor: Any?

  var body: some View {
    HStack {
      Text(displayString)
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )

      Button(isRecording ? "키를 누르세요..." : "입력") {
        if isRecording {
          stopRecording()
        } else {
          startRecording()
        }
      }
    }
  }

  private var displayString: String {
    if isRecording {
      if pressedModifiers.isEmpty && maxModifiers.isEmpty {
        return "단축키 입력"
      }
      return modifiersString(from: pressedModifiers.isEmpty ? maxModifiers.rawValue : pressedModifiers.rawValue)
    }

    let mods = modifiersString(from: modifiers)
    let key = keyCode == -1 ? "" : keyString(from: keyCode)
    if mods.isEmpty && key.isEmpty {
      return "없음"
    }
    return "\(mods)\(key)".trimmingCharacters(in: .whitespaces)
  }

  private func modifiersString(from rawValue: UInt) -> String {
    let flags = NSEvent.ModifierFlags(rawValue: rawValue)
    var result = ""
    if flags.contains(.control) { result += "⌃" }
    if flags.contains(.option) { result += "⌥" }
    if flags.contains(.shift) { result += "⇧" }
    if flags.contains(.command) { result += "⌘" }
    return result
  }

  private func keyString(from code: Int) -> String {
    switch code {
    case 49: return "스페이스"
    case 36: return "리턴"
    case 51: return "삭제"
    case 53: return "Esc"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default:
      return UnicodeScalar(keyToChar(code: CGKeyCode(code)))?.description.uppercased() ?? "?"
    }
  }

  func keyToChar(code: CGKeyCode) -> UInt32 {
    let map: [CGKeyCode: UInt32] = [
      0x00: 97, 0x01: 115, 0x02: 100, 0x03: 102, 0x04: 104, 0x05: 103, 0x06: 122, 0x07: 120,
      0x08: 99, 0x09: 118, 0x0B: 98, 0x0C: 113, 0x0D: 119, 0x0E: 101, 0x0F: 114, 0x10: 121,
      0x11: 116, 0x12: 49, 0x13: 50, 0x14: 51, 0x15: 52, 0x16: 54, 0x17: 53, 0x18: 61,
      0x19: 57, 0x1A: 55, 0x1B: 45, 0x1C: 56, 0x1D: 48, 0x1E: 93, 0x1F: 111, 0x20: 117,
      0x21: 91, 0x22: 105, 0x23: 112, 0x25: 108, 0x26: 106, 0x28: 107, 0x29: 59, 0x2A: 92,
      0x2B: 44, 0x2C: 47, 0x2D: 110, 0x2E: 109, 0x2F: 46, 0x32: 96
    ]
    return map[code] ?? 63
  }

  private func startRecording() {
    if !AccessibilityPermission.isTrusted() {
      PermissionPrompter.shared.requestAccessibilityForHotkeysIfNeeded()
      return
    }

    isRecording = true
    pressedModifiers = []
    maxModifiers = []

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
      if event.type == .flagsChanged {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.pressedModifiers = flags

        if flags.rawValue.nonzeroBitCount > self.maxModifiers.rawValue.nonzeroBitCount {
          self.maxModifiers = flags
        }

        if flags.isEmpty && !self.maxModifiers.isEmpty {
          DispatchQueue.main.async {
            self.modifiers = self.maxModifiers.rawValue
            self.keyCode = -1
            self.stopRecording()
          }
        }
        return nil
      }

      if event.type == .keyDown {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        DispatchQueue.main.async {
          self.modifiers = flags.rawValue
          self.keyCode = keyCode
          self.stopRecording()
        }
        return nil
      }

      return event
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
  }
}

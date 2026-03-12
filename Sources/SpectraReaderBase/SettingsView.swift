import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: SettingsStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Color.clear.frame(height: 0).focusable()

      Text("Reader Settings")
        .font(.title3)

      GroupBox(label: Text("Reader")) {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Enable OCR reader", isOn: $settings.readerEnabled)
          Toggle("Enable automatic OCR refresh", isOn: $settings.intervalEnabled)

          HStack {
            Text("Seconds")
              .frame(width: 70, alignment: .leading)
            Slider(value: $settings.intervalSeconds, in: 1.0...10, step: 0.5)
            TextField("Seconds", value: $settings.intervalSeconds, format: .number)
              .frame(width: 60)
          }
        }
        .padding(8)
      }

      GroupBox(label: Text("Lens")) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Opacity")
              .frame(width: 70, alignment: .leading)
            Slider(value: $settings.lensOpacity, in: 0.05...0.9, step: 0.05)
            Text("\(Int(settings.lensOpacity * 100))%")
              .frame(width: 50, alignment: .trailing)
          }

          HStack {
            Text("Font")
              .frame(width: 70, alignment: .leading)
            Slider(value: $settings.fontSizeOffset, in: -5...30, step: 1.0)
            Text("\(Int(settings.fontSizeOffset))pt")
              .frame(width: 50, alignment: .trailing)
          }

          HStack {
            Text("Color")
              .frame(width: 70, alignment: .leading)
            ColorPicker("", selection: settings.textColorBinding)
              .labelsHidden()
            Spacer()
          }

          HStack {
            Text("Tracking")
              .frame(width: 70, alignment: .leading)
            Slider(value: $settings.letterSpacing, in: -2...10, step: 0.1)
            Text(String(format: "%.1f", settings.letterSpacing))
              .frame(width: 50, alignment: .trailing)
          }
        }
        .padding(8)
      }

      GroupBox(label: Text("Global Hotkey")) {
        HotkeyRecorder(settings: settings)
          .padding(8)
      }

      Spacer()
    }
    .padding(18)
    .frame(width: 380)
    .fixedSize()
  }
}

struct HotkeyRecorder: View {
  @ObservedObject var settings: SettingsStore
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

      Button(isRecording ? "Press Keys..." : "Record") {
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
        return "Type shortcut"
      }
      return modifiersString(from: pressedModifiers.isEmpty ? maxModifiers.rawValue : pressedModifiers.rawValue)
    }

    let mods = modifiersString(from: settings.hotkeyModifiers)
    let key = settings.hotkeyKeyCode == -1 ? "" : keyString(from: settings.hotkeyKeyCode)
    if mods.isEmpty && key.isEmpty {
      return "None"
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
    case 49: return "Space"
    case 36: return "Return"
    case 51: return "Delete"
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
            self.settings.hotkeyModifiers = self.maxModifiers.rawValue
            self.settings.hotkeyKeyCode = -1
            self.stopRecording()
          }
        }
        return nil
      }

      if event.type == .keyDown {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        DispatchQueue.main.async {
          self.settings.hotkeyModifiers = flags.rawValue
          self.settings.hotkeyKeyCode = keyCode
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

import Foundation
import Combine

final class ReaderViewModel: ObservableObject {
  @Published var recognizedBlocks: [TextBlock]
  @Published var recognizedText: String
  @Published var currentPresetName: String
  @Published var assistantText: String
  @Published var lastSnapshotAt: Date?
  @Published var lastError: String?
  @Published var statusText: String
  @Published var isBusy: Bool

  init(
    recognizedBlocks: [TextBlock] = [],
    recognizedText: String = "",
    currentPresetName: String = "",
    assistantText: String = "",
    lastSnapshotAt: Date? = nil,
    lastError: String? = nil,
    statusText: String = "준비됨",
    isBusy: Bool = false
  ) {
    self.recognizedBlocks = recognizedBlocks
    self.recognizedText = recognizedText
    self.currentPresetName = currentPresetName
    self.assistantText = assistantText
    self.lastSnapshotAt = lastSnapshotAt
    self.lastError = lastError
    self.statusText = statusText
    self.isBusy = isBusy
  }
}

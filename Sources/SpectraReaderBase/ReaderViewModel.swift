import Foundation
import Combine

final class ReaderViewModel: ObservableObject {
  @Published var recognizedBlocks: [TextBlock]
  @Published var recognizedText: String
  @Published var currentPresetName: String
  @Published var assistantText: String
  @Published var assistantError: String?
  @Published var lastAssistantAt: Date?
  @Published var canCancelAssist: Bool
  @Published var sessionChunks: [ReadingChunk]
  @Published var sessionSnapshotCount: Int
  @Published var sessionAssistantText: String
  @Published var sessionAssistantError: String?
  @Published var lastSnapshotAt: Date?
  @Published var sessionLastUpdatedAt: Date?
  @Published var lastError: String?
  @Published var statusText: String
  @Published var isBusy: Bool

  init(
    recognizedBlocks: [TextBlock] = [],
    recognizedText: String = "",
    currentPresetName: String = "",
    assistantText: String = "",
    assistantError: String? = nil,
    lastAssistantAt: Date? = nil,
    canCancelAssist: Bool = false,
    sessionChunks: [ReadingChunk] = [],
    sessionSnapshotCount: Int = 0,
    sessionAssistantText: String = "",
    sessionAssistantError: String? = nil,
    lastSnapshotAt: Date? = nil,
    sessionLastUpdatedAt: Date? = nil,
    lastError: String? = nil,
    statusText: String = "준비됨",
    isBusy: Bool = false
  ) {
    self.recognizedBlocks = recognizedBlocks
    self.recognizedText = recognizedText
    self.currentPresetName = currentPresetName
    self.assistantText = assistantText
    self.assistantError = assistantError
    self.lastAssistantAt = lastAssistantAt
    self.canCancelAssist = canCancelAssist
    self.sessionChunks = sessionChunks
    self.sessionSnapshotCount = sessionSnapshotCount
    self.sessionAssistantText = sessionAssistantText
    self.sessionAssistantError = sessionAssistantError
    self.lastSnapshotAt = lastSnapshotAt
    self.sessionLastUpdatedAt = sessionLastUpdatedAt
    self.lastError = lastError
    self.statusText = statusText
    self.isBusy = isBusy
  }
}

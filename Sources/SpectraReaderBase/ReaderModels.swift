import Foundation
import CoreGraphics

struct HotkeyBinding: Codable, Equatable, Sendable {
  var modifiers: UInt
  var keyCode: Int

  static let none = HotkeyBinding(modifiers: 0, keyCode: -1)

  var isEmpty: Bool {
    modifiers == 0 && keyCode == -1
  }
}

struct AssistPreset: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var name: String
  var promptTemplate: String
  var isBuiltIn: Bool

  init(
    id: String = UUID().uuidString,
    name: String,
    promptTemplate: String,
    isBuiltIn: Bool
  ) {
    self.id = id
    self.name = name
    self.promptTemplate = promptTemplate
    self.isBuiltIn = isBuiltIn
  }

  static func defaultPresets() -> [AssistPreset] {
    [
      AssistPreset(
        name: "요약",
        promptTemplate: "다음 화면 내용을 3문장 이내로 핵심만 요약해줘.",
        isBuiltIn: true
      ),
      AssistPreset(
        name: "쉽게 설명",
        promptTemplate: "다음 화면 내용을 쉬운 한국어로 풀어서 설명해줘. 전문 용어는 짧게 덧붙여 설명해줘.",
        isBuiltIn: true
      ),
      AssistPreset(
        name: "핵심 행동",
        promptTemplate: "다음 화면에서 사용자가 지금 해야 할 행동이나 결정 사항만 짧은 목록으로 정리해줘.",
        isBuiltIn: true
      )
    ]
  }
}

struct ReadingSnapshot: Equatable, Sendable {
  let id: String
  let capturedAt: Date
  let blocks: [TextBlock]
  let plainText: String
  let sourceRect: CGRect

  init(
    id: String = UUID().uuidString,
    capturedAt: Date = Date(),
    blocks: [TextBlock],
    plainText: String,
    sourceRect: CGRect
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.blocks = blocks
    self.plainText = plainText
    self.sourceRect = sourceRect
  }
}

struct ReadingChunk: Identifiable, Equatable, Sendable {
  let id: String
  let text: String

  init(id: String = UUID().uuidString, text: String) {
    self.id = id
    self.text = text
  }
}

struct ReadingSession: Equatable, Sendable {
  static let overlapWindow = 12

  let id: String
  let createdAt: Date
  let updatedAt: Date
  let snapshotCount: Int
  let chunks: [ReadingChunk]
  let tailLines: [String]

  init(
    id: String = UUID().uuidString,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    snapshotCount: Int = 1,
    chunks: [ReadingChunk],
    tailLines: [String]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.snapshotCount = snapshotCount
    self.chunks = chunks
    self.tailLines = Array(tailLines.suffix(Self.overlapWindow))
  }

  var hasContent: Bool {
    !chunks.isEmpty
  }

  var text: String {
    chunks.map(\.text).joined(separator: "\n")
  }

  func asSnapshot(sourceRect: CGRect) -> ReadingSnapshot {
    ReadingSnapshot(
      id: id,
      capturedAt: updatedAt,
      blocks: [],
      plainText: text,
      sourceRect: sourceRect
    )
  }
}

struct AssistantResult: Equatable, Sendable {
  let presetID: String
  let snapshotID: String
  let outputText: String
  let completedAt: Date

  init(
    presetID: String,
    snapshotID: String,
    outputText: String,
    completedAt: Date = Date()
  ) {
    self.presetID = presetID
    self.snapshotID = snapshotID
    self.outputText = outputText
    self.completedAt = completedAt
  }
}

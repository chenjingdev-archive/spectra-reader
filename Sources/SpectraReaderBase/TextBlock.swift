import Foundation
import CoreGraphics

struct TextBlock: Identifiable {
  let id: UUID
  let text: String
  let boundingBox: CGRect

  init(id: UUID = UUID(), text: String, boundingBox: CGRect) {
    self.id = id
    self.text = text
    self.boundingBox = boundingBox
  }
}

import Foundation
import Combine

final class ReaderViewModel: ObservableObject {
  @Published var recognizedBlocks: [TextBlock]
  @Published var recognizedText: String
  @Published var statusText: String
  @Published var isBusy: Bool

  init(
    recognizedBlocks: [TextBlock] = [],
    recognizedText: String = "",
    statusText: String = "Idle",
    isBusy: Bool = false
  ) {
    self.recognizedBlocks = recognizedBlocks
    self.recognizedText = recognizedText
    self.statusText = statusText
    self.isBusy = isBusy
  }
}

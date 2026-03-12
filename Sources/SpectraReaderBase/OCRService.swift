import Foundation
import Vision
import CoreGraphics

struct OCRService: OCRRecognizing {
  func recognizeTextBlocks(in cgImage: CGImage) throws -> [TextBlock] {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.008

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    let observations = request.results ?? []
    var blocks: [TextBlock] = []
    blocks.reserveCapacity(observations.count)

    for observation in observations {
      guard let candidate = observation.topCandidates(1).first else { continue }
      let fullText = candidate.string
      let trimmedFull = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedFull.isEmpty else { continue }

      let ranges = Self.lineRanges(in: fullText)
      let lineCandidates = Self.lineCandidates(for: candidate, observation: observation, ranges: ranges)
      if lineCandidates.isEmpty {
        blocks.append(TextBlock(text: trimmedFull, boundingBox: observation.boundingBox))
        continue
      }

      let useROI = Self.shouldUseROI(lineCandidates: lineCandidates, observationBox: observation.boundingBox)

      for line in lineCandidates {
        let lineText = String(fullText[line.range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lineText.isEmpty else { continue }
        let boundingBox = useROI ? line.roiRect : line.globalRect
        blocks.append(TextBlock(text: lineText, boundingBox: boundingBox))
      }
    }

    return blocks.sorted { left, right in
      let yDiff = abs(left.boundingBox.midY - right.boundingBox.midY)
      if yDiff > 0.03 {
        return left.boundingBox.midY > right.boundingBox.midY
      }
      return left.boundingBox.minX < right.boundingBox.minX
    }
  }
}

private extension OCRService {
  struct LineCandidate {
    let range: Range<String.Index>
    let globalRect: CGRect
    let roiRect: CGRect
  }

  static func lineRanges(in text: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var start = text.startIndex

    while start < text.endIndex {
      if let newlineIndex = text[start...].firstIndex(where: { $0.isNewline }) {
        if start < newlineIndex {
          ranges.append(start..<newlineIndex)
        }
        start = text.index(after: newlineIndex)
        while start < text.endIndex, text[start].isNewline {
          start = text.index(after: start)
        }
      } else {
        ranges.append(start..<text.endIndex)
        break
      }
    }

    return ranges
  }

  static func lineCandidates(
    for candidate: VNRecognizedText,
    observation: VNRecognizedTextObservation,
    ranges: [Range<String.Index>]
  ) -> [LineCandidate] {
    let observationBox = observation.boundingBox
    var candidates: [LineCandidate] = []
    candidates.reserveCapacity(ranges.count)

    for range in ranges {
      guard let rectObservation = try? candidate.boundingBox(for: range) else { continue }
      let globalRect = rectObservation.boundingBox
      let roiRect = CGRect(
        x: observationBox.minX + globalRect.minX * observationBox.width,
        y: observationBox.minY + globalRect.minY * observationBox.height,
        width: globalRect.width * observationBox.width,
        height: globalRect.height * observationBox.height
      )
      candidates.append(LineCandidate(range: range, globalRect: globalRect, roiRect: roiRect))
    }

    return candidates
  }

  static func shouldUseROI(lineCandidates: [LineCandidate], observationBox: CGRect) -> Bool {
    guard let globalUnion = unionRect(lineCandidates.map(\.globalRect)),
          let roiUnion = unionRect(lineCandidates.map(\.roiRect))
    else {
      return false
    }

    let globalScore = iou(globalUnion, observationBox)
    let roiScore = iou(roiUnion, observationBox)
    return roiScore > globalScore
  }

  static func unionRect(_ rects: [CGRect]) -> CGRect? {
    guard var current = rects.first else { return nil }
    for rect in rects.dropFirst() {
      current = current.union(rect)
    }
    return current
  }

  static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }
    let intersectionArea = intersection.width * intersection.height
    let unionArea = a.width * a.height + b.width * b.height - intersectionArea
    guard unionArea > 0 else { return 0 }
    return intersectionArea / unionArea
  }
}

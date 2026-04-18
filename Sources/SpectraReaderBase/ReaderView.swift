import SwiftUI

struct ReaderView: View {
  @ObservedObject var viewModel: ReaderViewModel
  @ObservedObject var settings: SettingsStore

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.black.opacity(settings.overlayOpacity))

      readingSurface
        .padding(8)
    }
    .ignoresSafeArea()
  }

  private var readingSurface: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let blocks = viewModel.recognizedBlocks
      let dominantSize = Self.calculateDominantSize(from: blocks, in: size)

      ZStack(alignment: .topLeading) {
        if settings.hidesOverlayText {
          EmptyView()
        } else if blocks.isEmpty {
          Text("이 영역을 읽으려면 '읽기'를 누르세요.")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white.opacity(0.48))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ForEach(blocks) { block in
            let rect = Self.rect(for: block.boundingBox, in: size)
            let fontSize = Self.smartFontSize(for: rect, dominant: dominantSize)

            Text(block.text)
              .font(.system(size: fontSize, weight: .medium))
              .foregroundColor(.white.opacity(0.96))
              .lineLimit(1)
              .minimumScaleFactor(0.45)
              .frame(maxWidth: max(0, size.width - rect.minX), alignment: .topLeading)
              .offset(x: rect.minX, y: rect.minY)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .allowsHitTesting(false)
  }
}

private extension ReaderView {
  static func rect(for boundingBox: CGRect, in size: CGSize) -> CGRect {
    let x = boundingBox.minX * size.width
    let y = (1 - boundingBox.maxY) * size.height
    let width = boundingBox.width * size.width
    let height = boundingBox.height * size.height
    return CGRect(x: x, y: y, width: max(1, width), height: max(1, height))
  }

  static func calculateDominantSize(from blocks: [TextBlock], in viewSize: CGSize) -> CGFloat? {
    guard !blocks.isEmpty else { return nil }

    var counts: [Int: Int] = [:]

    for block in blocks {
      let rawSize = block.boundingBox.height * viewSize.height * 0.75
      let key = Int(round(rawSize))
      counts[key, default: 0] += 1
    }

    if let (modeSize, _) = counts.max(by: { $0.value < $1.value }) {
      return CGFloat(modeSize)
    }

    return nil
  }

  static func smartFontSize(for rect: CGRect, dominant: CGFloat?) -> CGFloat {
    let rawSize = rect.height * 0.75
    let finalSize: CGFloat

    if let dominant, abs(rawSize - dominant) <= 3.0 {
      finalSize = dominant
    } else {
      finalSize = round(rawSize)
    }

    return max(11, finalSize)
  }
}

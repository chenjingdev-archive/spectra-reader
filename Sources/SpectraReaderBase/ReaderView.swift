import SwiftUI

struct ReaderView: View {
  @ObservedObject var viewModel: ReaderViewModel
  @ObservedObject var settings: SettingsStore
  let onOpenSettings: () -> Void

  var body: some View {
    let blocks = settings.readerEnabled ? viewModel.recognizedBlocks : []

    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.black.opacity(settings.lensOpacity))

      GeometryReader { proxy in
        let size = proxy.size
        let dominantSize = Self.calculateDominantSize(from: blocks, in: size)

        ZStack(alignment: .topLeading) {
          ForEach(blocks) { block in
            let rect = Self.rect(for: block.boundingBox, in: size)
            let fontSize = Self.smartFontSize(for: rect, dominant: dominantSize, offset: settings.fontSizeOffset)

            Text(block.text)
              .font(.system(size: fontSize, weight: .medium))
              .foregroundColor(Color(hex: settings.textColorHex))
              .kerning(settings.letterSpacing)
              .lineLimit(1)
              .minimumScaleFactor(0.4)
              .shadow(color: .black.opacity(0.75), radius: 2, x: 0, y: 0)
              .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 0)
              .frame(maxWidth: max(0, size.width - rect.minX), alignment: .topLeading)
              .offset(x: rect.minX, y: rect.minY)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .allowsHitTesting(false)
      .id(settings.fontSizeOffset)
      .id(settings.letterSpacing)

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          StatusPill(text: viewModel.statusText, isBusy: viewModel.isBusy)

          Spacer()

          Button("Settings", action: onOpenSettings)
            .buttonStyle(.borderless)
            .foregroundColor(.white.opacity(0.7))
        }

        if !viewModel.recognizedText.isEmpty {
          Text(viewModel.recognizedText)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .lineLimit(3)
        }
      }
      .padding(14)
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(8)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        .padding(8)
    )
    .ignoresSafeArea()
  }
}

private struct StatusPill: View {
  let text: String
  let isBusy: Bool

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(isBusy ? Color.orange : Color.green.opacity(0.85))
        .frame(width: 7, height: 7)

      Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white.opacity(0.92))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.32))
    .clipShape(Capsule())
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
      let h = block.boundingBox.height * viewSize.height
      let rawSize = h * 0.75
      let key = Int(round(rawSize))
      counts[key, default: 0] += 1
    }

    if let (modeSize, _) = counts.max(by: { $0.value < $1.value }) {
      return CGFloat(modeSize)
    }

    return nil
  }

  static func smartFontSize(for rect: CGRect, dominant: CGFloat?, offset: Double) -> CGFloat {
    let rawSize = rect.height * 0.75
    var finalSize = rawSize

    if let dominant, abs(rawSize - dominant) <= 3.0 {
      finalSize = dominant
    } else if dominant == nil {
      finalSize = round(rawSize)
    }

    return max(10, finalSize + offset)
  }
}

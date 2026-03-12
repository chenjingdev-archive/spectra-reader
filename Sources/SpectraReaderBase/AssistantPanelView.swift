import SwiftUI

struct AssistantPanelView: View {
  @ObservedObject var viewModel: ReaderViewModel
  let onRead: () -> Void
  let onAssist: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      assistantBody
      sourcePreview
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var header: some View {
    HStack(spacing: 10) {
      StatusPill(
        text: viewModel.statusText,
        isBusy: viewModel.isBusy,
        hasError: viewModel.lastError != nil
      )

      if !viewModel.currentPresetName.isEmpty {
        Text(viewModel.currentPresetName)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundColor(.primary.opacity(0.8))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color.primary.opacity(0.08))
          .clipShape(Capsule())
      }

      Spacer()
    }
  }

  private var assistantBody: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("도움")
          .font(.headline)

        Spacer()

        if let lastSnapshotAt = viewModel.lastSnapshotAt {
          Text(lastSnapshotAt, style: .time)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
        }
      }

      Group {
        if !viewModel.assistantText.isEmpty {
          Text(viewModel.assistantText)
            .foregroundColor(.primary)
        } else if let lastError = viewModel.lastError {
          Text(lastError)
            .foregroundColor(.orange)
        } else if viewModel.lastSnapshotAt == nil {
          Text("선택된 프리셋으로 현재 오버레이 영역을 읽으려면 '도움'을 누르세요.")
            .foregroundColor(.secondary)
        } else {
          Text("도움 실행 시 최근 OCR 스냅샷을 재사용해 현재 프리셋을 다시 실행합니다.")
            .foregroundColor(.secondary)
        }
      }
      .font(.system(size: 13, weight: .regular))
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
    .background(Color.primary.opacity(0.04))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var sourcePreview: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("원문 미리보기")
          .font(.headline)

        Spacer()

        Button("읽기", action: onRead)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(viewModel.isBusy)

        Button("도움", action: onAssist)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(viewModel.isBusy)

        Button("설정", action: onOpenSettings)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }

      ScrollView {
        Text(viewModel.recognizedText.isEmpty ? "아직 OCR 스냅샷이 없습니다." : viewModel.recognizedText)
          .font(.system(size: 12, weight: .regular, design: .monospaced))
          .foregroundColor(viewModel.recognizedText.isEmpty ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .textSelection(.enabled)
      }
      .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(14)
    .background(Color.primary.opacity(0.04))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

private struct StatusPill: View {
  let text: String
  let isBusy: Bool
  let hasError: Bool

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(indicatorColor)
        .frame(width: 7, height: 7)

      Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.primary.opacity(0.9))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.primary.opacity(0.08))
    .clipShape(Capsule())
  }

  private var indicatorColor: Color {
    if hasError {
      return .orange
    }
    return isBusy ? .blue : .green.opacity(0.9)
  }
}

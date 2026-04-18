import SwiftUI

struct AssistantPanelView: View {
  @ObservedObject var viewModel: ReaderViewModel
  let onSnapshot: () -> Void
  let onAssist: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        actionBar
        assistantSection
        sourceSection
      }
      .padding(16)
    }
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
        hasError: viewModel.lastError != nil || viewModel.assistantError != nil
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

  private var actionBar: some View {
    HStack(spacing: 8) {
      Button("스냅샷", action: onSnapshot)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(viewModel.isBusy)

      Button(viewModel.canCancelAssist ? "취소" : "도움", action: onAssist)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled((!viewModel.canCancelAssist && sourceChunks.isEmpty) || (viewModel.isBusy && !viewModel.canCancelAssist))

      Spacer()

      Button("설정", action: onOpenSettings)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }

  private var assistantSection: some View {
    infoSection(
      title: "도움",
      timestamp: assistantTimestamp,
      detail: assistantDetail,
      text: viewModel.assistantText,
      error: viewModel.assistantError,
      emptyText: "도움을 실행하면 누적된 스냅샷으로 AI를 호출합니다. 원문은 초기화 전까지 유지됩니다."
    )
  }

  private var sourceSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("원문")
          .font(.headline)

        Spacer()

        if let detail = sourceDetail, !detail.isEmpty {
          Text(detail)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
        }

        if let timestamp = sourceTimestamp {
          Text(timestamp, style: .time)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
        }
      }

      if sourceChunks.isEmpty {
        Text("스냅샷을 누를 때마다 원문이 여기에 계속 이어 붙습니다.")
          .font(.system(size: 13, weight: .regular))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
      } else {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(sourceChunks) { chunk in
            Text(verbatim: chunk.text)
              .foregroundColor(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .font(.system(size: 13, weight: .regular))
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .textSelection(.enabled)
      }
    }
    .padding(14)
    .background(Color.primary.opacity(0.04))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func infoSection(
    title: String,
    timestamp: Date?,
    detail: String?,
    text: String,
    error: String?,
    emptyText: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.headline)

        Spacer()

        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
        }

        if let timestamp {
          Text(timestamp, style: .time)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
        }
      }

      Group {
        if !text.isEmpty {
          Text(verbatim: text)
            .foregroundColor(.primary)
        } else if let error {
          Text(verbatim: error)
            .foregroundColor(.orange)
        } else {
          Text(verbatim: emptyText)
            .foregroundColor(.secondary)
        }
      }
      .font(.system(size: 13, weight: .regular))
      .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
      .textSelection(.enabled)
    }
    .padding(14)
    .background(Color.primary.opacity(0.04))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

private extension AssistantPanelView {
  var sourceChunks: [ReadingChunk] {
    viewModel.sessionChunks
  }

  var sourceTimestamp: Date? {
    viewModel.sessionLastUpdatedAt
  }

  var sourceDetail: String? {
    guard viewModel.sessionSnapshotCount > 0 else { return nil }
    return "\(viewModel.sessionSnapshotCount)개 스냅샷"
  }

  var assistantTimestamp: Date? {
    viewModel.lastAssistantAt
  }

  var assistantDetail: String? {
    viewModel.assistantText.isEmpty && viewModel.assistantError == nil ? nil : "AI 결과"
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

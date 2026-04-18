import Foundation

enum AssistantError: LocalizedError, Equatable {
  case codexUnavailable
  case invalidResponse
  case processLaunchFailed(String)
  case processFailed(status: Int32, message: String)
  case apiRequestFailed(status: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .codexUnavailable:
      return "Codex CLI를 찾을 수 없습니다."
    case .invalidResponse:
      return "도우미가 올바른 응답을 반환하지 않았습니다."
    case let .processLaunchFailed(message):
      return message.isEmpty ? "도우미 프로세스를 실행할 수 없습니다." : message
    case let .processFailed(_, message):
      return message.isEmpty ? "도우미 프로세스가 오류와 함께 종료되었습니다." : message
    case let .apiRequestFailed(_, message):
      return message.isEmpty ? "OpenAI 응답 생성 요청이 실패했습니다." : message
    }
  }
}

struct HelperAssistantService: AssistantProviding {
  let command: String

  func run(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    onEvent: @escaping @Sendable (AssistantStreamEvent) -> Void
  ) async throws -> AssistantResult {
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedCommand.isEmpty {
      return try await CustomHelperAssistantService(command: trimmedCommand)
        .run(snapshot: snapshot, preset: preset, onEvent: onEvent)
    }

    if let apiKey = OpenAIKeyLoader.load() {
      return try await ResponsesAPIService(apiKey: apiKey)
        .run(snapshot: snapshot, preset: preset, onEvent: onEvent)
    }

    return try await CodexCLIService().run(snapshot: snapshot, preset: preset, onEvent: onEvent)
  }
}

private struct CustomHelperAssistantService: AssistantProviding {
  let command: String

  func run(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    onEvent: @escaping @Sendable (AssistantStreamEvent) -> Void
  ) async throws -> AssistantResult {
    let request = HelperRequest(
      presetName: preset.name,
      prompt: preset.promptTemplate,
      text: snapshot.plainText
    )

    let requestData = try JSONEncoder().encode(request) + Data([0x0A])
    let processResult = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/bin/zsh"),
      arguments: ["-lc", command],
      stdinData: requestData
    )

    let stderr = processResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard processResult.terminationStatus == 0 else {
      throw AssistantError.processFailed(status: processResult.terminationStatus, message: stderr)
    }

    let stdout = processResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stdout.isEmpty else {
      throw AssistantError.invalidResponse
    }

    if let line = stdout.split(whereSeparator: \.isNewline).first,
       let data = line.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(HelperResponse.self, from: data),
       let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
       !outputText.isEmpty {
      onEvent(.textDelta(outputText))
      return AssistantResult(
        presetID: preset.id,
        snapshotID: snapshot.id,
        outputText: outputText
      )
    }

    onEvent(.textDelta(stdout))
    return AssistantResult(
      presetID: preset.id,
      snapshotID: snapshot.id,
      outputText: stdout
    )
  }
}

private struct ResponsesAPIService: AssistantProviding {
  let apiKey: String
  let session: URLSession = .shared

  func run(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    onEvent: @escaping @Sendable (AssistantStreamEvent) -> Void
  ) async throws -> AssistantResult {
    let request = try Self.makeRequest(
      apiKey: apiKey,
      prompt: CodexCLIService.buildPrompt(snapshot: snapshot, preset: preset)
    )

    let (bytes, response) = try await session.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AssistantError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let responseText = try await Self.readBody(from: bytes)
      throw AssistantError.apiRequestFailed(
        status: httpResponse.statusCode,
        message: Self.extractErrorMessage(from: responseText)
      )
    }

    var pendingEventLines: [String] = []
    var accumulatedText = ""

    for try await rawLine in bytes.lines {
      try Task.checkCancellation()

      if rawLine.isEmpty {
        if let event = Self.parseEvent(from: pendingEventLines) {
          switch event.type {
          case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
              accumulatedText += delta
              onEvent(.textDelta(delta))
            }
          case "error":
            throw AssistantError.apiRequestFailed(
              status: httpResponse.statusCode,
              message: event.error?.message ?? "OpenAI 스트리밍 응답 처리에 실패했습니다."
            )
          default:
            if accumulatedText.isEmpty,
               let completedText = event.response?.outputText,
               !completedText.isEmpty {
              accumulatedText = completedText
            }
          }
        }

        pendingEventLines.removeAll(keepingCapacity: true)
        continue
      }

      pendingEventLines.append(rawLine)
    }

    if let event = Self.parseEvent(from: pendingEventLines),
       accumulatedText.isEmpty,
       let completedText = event.response?.outputText,
       !completedText.isEmpty {
      accumulatedText = completedText
    }

    let finalText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !finalText.isEmpty else {
      throw AssistantError.invalidResponse
    }

    return AssistantResult(
      presetID: preset.id,
      snapshotID: snapshot.id,
      outputText: finalText
    )
  }

  private static func makeRequest(apiKey: String, prompt: String) throws -> URLRequest {
    guard let url = URL(string: "https://api.openai.com/v1/responses") else {
      throw AssistantError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      ResponsesCreateRequest(
        model: ProcessInfo.processInfo.environment["SPECTRA_READER_OPENAI_MODEL"] ?? "gpt-5.4",
        input: prompt,
        stream: true
      )
    )
    return request
  }

  private static func parseEvent(from rawLines: [String]) -> ResponsesStreamEvent? {
    guard !rawLines.isEmpty else { return nil }

    let payload = rawLines
      .compactMap { line -> String? in
        guard line.hasPrefix("data:") else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      }
      .joined(separator: "\n")

    guard !payload.isEmpty, payload != "[DONE]" else { return nil }
    guard let data = payload.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(ResponsesStreamEvent.self, from: data)
  }

  private static func readBody(from bytes: URLSession.AsyncBytes) async throws -> String {
    var chunks: [String] = []
    for try await line in bytes.lines {
      chunks.append(line)
    }
    return chunks.joined(separator: "\n")
  }

  private static func extractErrorMessage(from text: String) -> String {
    guard let data = text.data(using: .utf8),
          let envelope = try? JSONDecoder().decode(ResponsesErrorEnvelope.self, from: data),
          let message = envelope.error?.message,
          !message.isEmpty
    else {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return message
  }
}

struct CodexCLIService: AssistantProviding {
  func run(
    snapshot: ReadingSnapshot,
    preset: AssistPreset,
    onEvent: @escaping @Sendable (AssistantStreamEvent) -> Void
  ) async throws -> AssistantResult {
    let prompt = Self.buildPrompt(snapshot: snapshot, preset: preset)
    let processResult = try await ProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: Self.commandArguments(),
      stdinData: prompt.data(using: .utf8)
    )

    let stdout = processResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = processResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

    guard processResult.terminationStatus == 0 else {
      if stderr.contains("No such file or directory") || stderr.contains("command not found") {
        throw AssistantError.codexUnavailable
      }
      throw AssistantError.processFailed(
        status: processResult.terminationStatus,
        message: stderr.isEmpty ? stdout : stderr
      )
    }

    let finalText = Self.extractAgentMessage(from: stdout).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !finalText.isEmpty else {
      throw AssistantError.invalidResponse
    }

    onEvent(.textDelta(finalText))
    return AssistantResult(
      presetID: preset.id,
      snapshotID: snapshot.id,
      outputText: finalText
    )
  }

  static func projectRootURL() -> URL {
    if let overrideRoot = ProcessInfo.processInfo.environment["SPECTRA_READER_ROOT"], !overrideRoot.isEmpty {
      return URL(fileURLWithPath: overrideRoot, isDirectory: true)
    }

    return URL(fileURLWithPath: #filePath, isDirectory: false)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static func executionRootURL() -> URL {
    if let overrideRoot = ProcessInfo.processInfo.environment["SPECTRA_READER_ASSISTANT_ROOT"],
       !overrideRoot.isEmpty {
      return URL(fileURLWithPath: overrideRoot, isDirectory: true)
    }

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("spectra-reader-assistant", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
    return root
  }

  static func modelName() -> String {
    ProcessInfo.processInfo.environment["SPECTRA_READER_CODEX_MODEL"] ?? "gpt-5.4"
  }

  static func commandArguments() -> [String] {
    [
      "codex",
      "exec",
      "-",
      "-C",
      executionRootURL().path,
      "--skip-git-repo-check",
      "--ephemeral",
      "--sandbox",
      "read-only",
      "--color",
      "never",
      "--json",
      "--disable",
      "apps",
      "--disable",
      "multi_agent",
      "--disable",
      "js_repl",
      "--disable",
      "unified_exec",
      "--disable",
      "shell_snapshot",
      "-c",
      "mcp_servers.chrome-devtools.enabled=false",
      "-c",
      "approval_policy=\"never\"",
      "-c",
      "model_reasoning_effort=\"low\"",
      "-m",
      modelName()
    ]
  }

  static func buildPrompt(snapshot: ReadingSnapshot, preset: AssistPreset) -> String {
    [
      "너는 화면 읽기 보조 앱의 도우미다.",
      "응답은 간결한 일반 텍스트로만 작성해라.",
      "특별한 지시가 없으면 한국어로 답해라.",
      "",
      "프리셋 이름: \(preset.name)",
      "프리셋 지시:",
      preset.promptTemplate,
      "",
      "OCR 원문:",
      snapshot.plainText
    ].joined(separator: "\n")
  }

  private static func extractAgentMessage(from stdout: String) -> String {
    for line in stdout.split(whereSeparator: \.isNewline) {
      guard line.first == "{",
            let data = line.data(using: .utf8),
            let event = try? JSONDecoder().decode(CodexExecEvent.self, from: data),
            event.type == "item.completed",
            event.item?.type == "agent_message",
            let text = event.item?.text,
            !text.isEmpty
      else {
        continue
      }

      return text
    }

    return stdout
  }
}

private enum OpenAIKeyLoader {
  static func load() -> String? {
    if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !apiKey.isEmpty {
      return apiKey
    }

    let authFile = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/auth.json", isDirectory: false)

    guard let data = try? Data(contentsOf: authFile),
          let payload = try? JSONDecoder().decode(CodexAuthPayload.self, from: data),
          let apiKey = payload.openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
          !apiKey.isEmpty
    else {
      return nil
    }

    return apiKey
  }
}

private enum ProcessRunner {
  static func run(
    executableURL: URL,
    arguments: [String],
    stdinData: Data?
  ) async throws -> ProcessResult {
    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.executableURL = executableURL
    process.arguments = arguments

    let stdoutTask = Task {
      try await readAll(from: stdoutPipe.fileHandleForReading)
    }
    let stderrTask = Task {
      try await readAll(from: stderrPipe.fileHandleForReading)
    }

    return try await withTaskCancellationHandler {
      do {
        try process.run()
      } catch {
        stdoutTask.cancel()
        stderrTask.cancel()
        throw AssistantError.processLaunchFailed(error.localizedDescription)
      }

      if let stdinData, !stdinData.isEmpty {
        stdinPipe.fileHandleForWriting.write(stdinData)
      }
      try? stdinPipe.fileHandleForWriting.close()

      let terminationStatus = try await waitUntilExit(process)
      let stdout = try await stdoutTask.value
      let stderr = try await stderrTask.value
      return ProcessResult(
        stdout: stdout,
        stderr: stderr,
        terminationStatus: terminationStatus
      )
    } onCancel: {
      try? stdinPipe.fileHandleForWriting.close()
      stdoutTask.cancel()
      stderrTask.cancel()

      if process.isRunning {
        process.terminate()
      }
    }
  }

  private static func waitUntilExit(_ process: Process) async throws -> Int32 {
    await Task.detached(priority: .utility) {
      process.waitUntilExit()
      return process.terminationStatus
    }.value
  }

  private static func readAll(from handle: FileHandle) async throws -> String {
    var collectedLines: [String] = []
    for try await line in handle.bytes.lines {
      collectedLines.append(line)
    }
    return collectedLines.joined(separator: "\n")
  }
}

private struct ProcessResult {
  let stdout: String
  let stderr: String
  let terminationStatus: Int32
}

private struct ResponsesCreateRequest: Encodable {
  let model: String
  let input: String
  let stream: Bool
}

private struct ResponsesStreamEvent: Decodable {
  let type: String
  let delta: String?
  let error: ResponsesErrorPayload?
  let response: ResponsesCompletedPayload?
}

private struct ResponsesCompletedPayload: Decodable {
  let output: [ResponsesOutputItem]?

  var outputText: String? {
    output?
      .flatMap { $0.content ?? [] }
      .compactMap(\.text)
      .joined()
  }
}

private struct ResponsesOutputItem: Decodable {
  let content: [ResponsesOutputContent]?
}

private struct ResponsesOutputContent: Decodable {
  let text: String?
}

private struct ResponsesErrorEnvelope: Decodable {
  let error: ResponsesErrorPayload?
}

private struct ResponsesErrorPayload: Decodable {
  let message: String?
}

private struct CodexExecEvent: Decodable {
  let type: String
  let item: CodexExecItem?
}

private struct CodexExecItem: Decodable {
  let type: String
  let text: String?
}

private struct CodexAuthPayload: Decodable {
  let openAIAPIKey: String?

  enum CodingKeys: String, CodingKey {
    case openAIAPIKey = "OPENAI_API_KEY"
  }
}

private struct HelperRequest: Codable {
  let presetName: String
  let prompt: String
  let text: String
}

private struct HelperResponse: Decodable {
  let outputText: String?

  enum CodingKeys: String, CodingKey {
    case outputText
    case output
    case text
    case result
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    outputText =
      try container.decodeIfPresent(String.self, forKey: .outputText) ??
      container.decodeIfPresent(String.self, forKey: .output) ??
      container.decodeIfPresent(String.self, forKey: .text) ??
      container.decodeIfPresent(String.self, forKey: .result)
  }
}

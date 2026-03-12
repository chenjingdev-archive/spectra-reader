import Foundation

enum AssistantError: LocalizedError, Equatable {
  case codexUnavailable
  case invalidResponse
  case processLaunchFailed(String)
  case processFailed(status: Int32, message: String)

  var errorDescription: String? {
    switch self {
    case .codexUnavailable:
      return "Codex CLI를 찾을 수 없습니다."
    case .invalidResponse:
      return "Codex가 올바른 응답을 반환하지 않았습니다."
    case let .processLaunchFailed(message):
      return message.isEmpty ? "Codex CLI를 실행할 수 없습니다." : message
    case let .processFailed(_, message):
      return message.isEmpty ? "Codex CLI가 오류와 함께 종료되었습니다." : message
    }
  }
}

struct HelperAssistantService: AssistantProviding {
  let command: String

  func run(snapshot: ReadingSnapshot, preset: AssistPreset) async throws -> AssistantResult {
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedCommand.isEmpty {
      return try await CodexCLIService().run(snapshot: snapshot, preset: preset)
    }

    return try await CustomHelperAssistantService(command: trimmedCommand).run(snapshot: snapshot, preset: preset)
  }
}

private struct CustomHelperAssistantService: AssistantProviding {
  let command: String

  func run(snapshot: ReadingSnapshot, preset: AssistPreset) async throws -> AssistantResult {
    let request = HelperRequest(
      presetName: preset.name,
      prompt: preset.promptTemplate,
      text: snapshot.plainText
    )

    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]

    do {
      try process.run()
    } catch {
      throw AssistantError.processLaunchFailed(error.localizedDescription)
    }

    let requestData = try JSONEncoder().encode(request) + Data([0x0A])
    stdinPipe.fileHandleForWriting.write(requestData)
    try? stdinPipe.fileHandleForWriting.close()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let stderr = String(data: stderrData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard process.terminationStatus == 0 else {
      throw AssistantError.processFailed(status: process.terminationStatus, message: stderr)
    }

    let stdout = String(data: stdoutData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !stdout.isEmpty else {
      throw AssistantError.invalidResponse
    }

    if let line = stdout.split(whereSeparator: \.isNewline).first,
       let data = line.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(HelperResponse.self, from: data),
       let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
       !outputText.isEmpty {
      return AssistantResult(
        presetID: preset.id,
        snapshotID: snapshot.id,
        outputText: outputText
      )
    }

    return AssistantResult(
      presetID: preset.id,
      snapshotID: snapshot.id,
      outputText: stdout
    )
  }
}

struct CodexCLIService: AssistantProviding {
  func run(snapshot: ReadingSnapshot, preset: AssistPreset) async throws -> AssistantResult {
    let prompt = Self.buildPrompt(snapshot: snapshot, preset: preset)
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spectra-reader-codex-\(UUID().uuidString)")
      .appendingPathExtension("txt")

    defer {
      try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "codex",
      "exec",
      "-",
      "-C",
      Self.projectRootURL().path,
      "--skip-git-repo-check",
      "--sandbox",
      "read-only",
      "--color",
      "never",
      "--output-last-message",
      outputURL.path
    ]

    do {
      try process.run()
    } catch {
      throw AssistantError.processLaunchFailed(error.localizedDescription)
    }

    if let promptData = prompt.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(promptData)
    }
    try? stdinPipe.fileHandleForWriting.close()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let stdout = String(data: stdoutData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0 else {
      if stderr.contains("No such file or directory") || stderr.contains("command not found") {
        throw AssistantError.codexUnavailable
      }
      throw AssistantError.processFailed(
        status: process.terminationStatus,
        message: stderr.isEmpty ? stdout : stderr
      )
    }

    let outputText = (try? String(contentsOf: outputURL, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let finalText = outputText?.isEmpty == false ? outputText! : stdout
    guard !finalText.isEmpty else {
      throw AssistantError.invalidResponse
    }

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

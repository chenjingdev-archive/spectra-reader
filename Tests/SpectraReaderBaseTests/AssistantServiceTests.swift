import Foundation
import Testing
@testable import SpectraReaderBase

struct AssistantServiceTests {
  @Test
  func codexPromptIncludesPresetAndOCRText() {
    let snapshot = ReadingSnapshot(
      blocks: [TextBlock(text: "로그인 버튼", boundingBox: .zero)],
      plainText: "로그인 버튼",
      sourceRect: .zero
    )
    let preset = AssistPreset(name: "요약", promptTemplate: "짧게 요약해줘.", isBuiltIn: true)

    let prompt = CodexCLIService.buildPrompt(snapshot: snapshot, preset: preset)

    #expect(prompt.contains("프리셋 이름: 요약"))
    #expect(prompt.contains("짧게 요약해줘."))
    #expect(prompt.contains("OCR 원문:\n로그인 버튼"))
  }

  @Test
  func codexProjectRootResolvesToWorkspace() {
    let root = CodexCLIService.projectRootURL()
    #expect(root.lastPathComponent == "spectra-reader")
  }

  @Test
  func codexExecutionRootUsesScratchDirectory() {
    let root = CodexCLIService.executionRootURL()
    #expect(root.lastPathComponent == "spectra-reader-assistant")
  }

  @Test
  func codexCLIUsesGPT54AndLeanExecFlags() {
    let arguments = CodexCLIService.commandArguments()

    #expect(arguments.contains("gpt-5.4"))
    #expect(arguments.contains("--json"))
    #expect(arguments.contains("apps"))
    #expect(arguments.contains("multi_agent"))
    #expect(arguments.contains("js_repl"))
    #expect(arguments.contains("unified_exec"))
    #expect(arguments.contains("shell_snapshot"))
    #expect(arguments.contains("mcp_servers.chrome-devtools.enabled=false"))
    #expect(arguments.contains("model_reasoning_effort=\"low\""))
    #expect(arguments.contains(CodexCLIService.executionRootURL().path))
  }
}

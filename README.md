# Spectra Reader Base

`translator-app`에서 번역 관련 의존성을 제거한 뒤, `읽기 + 필요 시 LLM 도움`에 집중하도록 다시 구성한 macOS SwiftPM 앱입니다.

포함된 것:
- 화면 캡처
- Vision OCR
- 최소 오버레이 리더 창
- 수동 `Read` / `Assist` 액션
- 수동 `추가 읽기` 기반 누적 읽기 세션
- `세션 초기화`와 중복 줄 제거
- `현재 화면 도움` / `누적 세션 도움` 분리
- 프리셋 기반 Codex 도움 호출
- 상태바 토글
- 글로벌 단축키
- 화면 기록 / 접근성 권한 요청

빠진 것:
- 자동 OCR 갱신
- 시각 스타일 커스터마이징
- 이미지 직접 LLM 입력
- `AXUIElement` 기반 접근성 읽기
- TTS 출력

실행:

```bash
cd /Users/chenjing/dev/spectra-reader
swift run spectra-reader-base
```

빌드:

```bash
cd /Users/chenjing/dev/spectra-reader
swift build
```

테스트:

```bash
cd /Users/chenjing/dev/spectra-reader
swift test
```

Codex 연결:
1. 기본값으로 설치된 `codex` CLI를 직접 사용합니다. 별도 경로 입력 없이 `Assist`를 누르면 됩니다.
2. `codex login`이 끝나 있어야 도움 호출이 바로 동작합니다.
3. 설정 화면의 `고급: 외부 헬퍼 명령어`는 다른 CLI를 붙일 때만 사용합니다.

추가 메모:
- 긴 컨텐츠/스크롤 처리 TODO는 [docs/TODO.md](/Users/chenjing/dev/spectra-reader/docs/TODO.md)에 정리합니다.

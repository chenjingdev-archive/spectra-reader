# Spectra Reader Base

`translator-app`에서 번역 관련 의존성을 제거하고, 화면 리더 베이스로 재사용할 수 있는 최소 코어만 분리한 macOS SwiftPM 앱입니다.

포함된 것:
- 화면 캡처
- Vision OCR
- 렌즈 오버레이 창
- 상태바 토글
- 글로벌 단축키
- 화면 기록 / 접근성 권한 요청
- 주기적 OCR 갱신

빠진 것:
- `Translation.framework`
- 번역 세션 관리
- 블록 단위 번역 파이프라인
- follow / 마우스 액션 특화 기능

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

다음 단계 추천:
1. `ReaderCoordinator` 뒤에 LLM 서비스 추가
2. `AVSpeechSynthesizer`로 음성 출력 추가
3. OCR 외에 `AXUIElement` 기반 접근성 읽기 경로 추가
4. 오버레이 중심 UX를 음성 중심 UX로 전환

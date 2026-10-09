# LLM Usage

macOS 상태 막대에서 Codex CLI와 Claude Code CLI의 사용 한도를 확인하고, 이 Mac에서 남긴 CLI 기록을 토큰·모델별로 집계하는 SwiftUI 앱입니다. 앱 이름은 **LLM Usage**, 실행 파일과 Swift Package 이름은 `LLMUsage`입니다.

상태 막대에는 `Codex 72% · Claude 41%`처럼 남은 한도를 표시합니다. 항목을 누르면 한도 초기화 시각, 오늘 또는 최근 7일의 토큰 합계, 모델별 합계를 볼 수 있습니다. 알 수 없는 값은 `—`로 표시합니다.

## 요구 사항

- macOS 14 이상
- Xcode 또는 Xcode Command Line Tools의 Swift 6 도구 체인
- 선택 사항: 로그인된 Codex CLI 및 Claude Code CLI

서드파티 패키지와 Xcode 프로젝트는 사용하지 않습니다.

## 실행과 검증

개발 중에는 다음 명령으로 빌드와 테스트를 실행합니다. 전체 Xcode가 설치된 Mac에서는 스크립트와 같은 개발자 도구 경로를 사용하면 Command Line Tools 선택 상태와 무관하게 동작합니다.

```zsh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/private/tmp/llmusage-clang-cache
export SWIFT_MODULECACHE_PATH=/private/tmp/llmusage-swift-module-cache

swift build --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache
swift test --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache
swift run --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache LLMUsage --diagnose
swift run --disable-sandbox --cache-path /private/tmp/llmusage-swift-cache LLMUsage --screenshot /private/tmp/llmusage-panel.png
```

`--diagnose`는 대화 내용 없이 발견한 이벤트 수, 토큰 수, 모델 수와 사용 가능한 한도 스냅샷만 출력합니다. 실제 앱은 다음으로 빌드합니다.

`--screenshot`은 실제 SwiftUI 패널을 숫자로만 구성한 미리보기 데이터로 렌더링합니다. 로컬 CLI 기록이나 설정 파일을 읽거나 바꾸지 않으므로, 밝은색·다크 모드 레이아웃 확인에 쓸 수 있습니다.

```zsh
./Scripts/build-app.sh
open "dist/LLM Usage.app"
```

빌드 스크립트는 `dist/LLM Usage.app`을 만들고 현재 Mac에서 실행할 수 있도록 ad-hoc 서명합니다. 배포용 Developer ID 서명·공증은 아직 포함하지 않습니다.

## Codex 전역 에이전트 규칙

이 저장소에는 책임별 모듈 구성을 요구하는 규칙이 적용되어 있습니다. 같은 규칙을 Codex 전역 규칙에 추가하려는 시도는 프로젝트 밖의 `~/.codex/AGENTS.md` 쓰기가 현재 샌드박스 정책에서 거절되어 자동 적용하지 못했습니다. 준비된 [패치](docs/global-agent-rules.patch)를 검토한 뒤, 원할 때 직접 적용할 수 있습니다.

```zsh
cd ~/.codex
git apply /Users/jude/Documents/llm-usage/docs/global-agent-rules.patch
```

이 명령은 Git 저장소가 아닌 디렉터리에서도 파일 패치를 적용하는 용도로 사용할 수 있습니다. 적용 전에는 `git apply --check /Users/jude/Documents/llm-usage/docs/global-agent-rules.patch`로 확인할 수 있습니다.

## 데이터가 오는 곳

| 표시 | 출처 | 갱신 방식 |
| --- | --- | --- |
| Codex 한도 | `codex app-server --stdio`의 `account/rateLimits/read` | 시작 시와 60초마다 |
| Claude 한도 | Claude Code statusline 입력에서 추출한 `rate_limits` | Claude 응답 후, 앱이 매분 읽음 |
| Codex·Claude 토큰과 모델 | `~/.codex`와 `~/.claude` 아래의 로컬 JSONL 사용 기록 | 시작·수동 새로고침·최대 5분 간격 |

`CODEX_HOME`과 `CLAUDE_CONFIG_DIR`이 설정되어 있으면 기본 경로 대신 각각 사용합니다. 토큰 통계는 **이 Mac의 해당 로그에 있는 기록만** 나타냅니다. 다른 Mac, 웹, API, 삭제된 로그의 사용량은 포함되지 않을 수 있습니다.

한도와 토큰은 별개의 지표입니다. 한도의 비율은 제공자가 반환한 계정 제한 값이고, 토큰 표는 로컬 기록의 합계입니다. 토큰 수로 구독 한도나 청구 금액을 추정하지 않으며, 이 앱은 비용 또는 청구액을 표시하지 않습니다.

## Claude Code 한도 연결

Claude Code는 statusline 명령이 응답을 처리할 때 앱에 JSON을 전달할 수 있습니다. 앱 패널의 **Claude 연결… → 연결 설정 적용**을 누르면 `settings.json`을 읽고, statusline이 없을 때만 설정을 추가합니다. 이미 파일이 있으면 먼저 UUID가 붙은 `settings.llmusage-backup-…json` 백업을 만듭니다.

기존 `statusLine`이 있으면 앱은 이를 덮어쓰지 않고 연결을 중단합니다. 기존 statusline의 화면 출력을 보존하려면, 신뢰하는 기존 명령을 직접 호출하는 래퍼를 만들어 `statusLine.command`에 그 래퍼 경로를 설정하세요. 앱은 기존 명령을 자동 실행하거나 변경하지 않습니다.

예를 들어 기존 statusline이 단일 로컬 스크립트라면 다음처럼 래퍼를 작성할 수 있습니다. `ORIGINAL_STATUSLINE`은 검토한 로컬 실행 파일의 절대 경로로 바꾸세요. 복잡한 셸 파이프라인은 먼저 별도 로컬 스크립트에 넣어 같은 방식으로 참조합니다.

```zsh
#!/bin/zsh
set -eu

LLM_USAGE="$HOME/Documents/llm-usage/dist/LLM Usage.app/Contents/MacOS/LLMUsage"
ORIGINAL_STATUSLINE="/absolute/path/to/your/trusted-statusline-script"

cat | tee >("$LLM_USAGE" --capture-claude >/dev/null 2>&1) | "$ORIGINAL_STATUSLINE"
```

이 래퍼는 같은 statusline JSON을 메모리의 파이프로 LLM Usage와 기존 명령에 각각 전달합니다. 전체 JSON을 임시 파일에 쓰지 않습니다. 기존 명령의 표준 출력은 그대로 Claude Code로 전달되고, LLM Usage의 짧은 상태 출력은 버립니다. 신뢰하지 않는 명령이나 경로를 이 예시에 넣지 마세요.

연결을 적용한 뒤 새 Claude Code 세션에서 응답을 한 번 받아야 한도가 보일 수 있습니다. Claude statusline이 실행되지 않는 동안 마지막 수치에는 수집 시각과 오래된 기록 표시가 붙습니다.

## 정확도와 개인정보 범위

- 앱은 대화 본문, 프롬프트, 응답, 인증 정보, API 키를 별도 저장하거나 전송하지 않습니다. Claude 한도 연결은 `~/Library/Application Support/LLMUsage/claude-quota.json`에 한도 창·수집 시각만 0600 권한으로 저장합니다.
- Codex App Server의 계정 한도 조회와 Claude Code의 statusline 기능은 각 CLI가 제공하는 인터페이스를 이용합니다. 로그인 상태, 플랜, CLI 버전에 따라 값이 없거나 달라질 수 있습니다.
- 로컬 JSONL 구조와 토큰 필드는 공개된 장기 안정 회계 API가 아닙니다. CLI 업데이트로 구조가 바뀌면 토큰 집계가 비어 있거나 달라질 수 있습니다.
- Codex는 같은 세션 ID의 로그를 한 번만 사용하고, Claude는 메시지·요청 ID가 겹칠 때 더 완전한 기록 하나를 사용합니다. 세션 포크, 복사된 로그, 누락된 ID, 재시도 형식 변경은 과소·과대 집계의 원인이 될 수 있습니다.
- 초기화 시각이 이미 지난 한도는 100%로 되돌려 추정하지 않습니다. 패널은 `갱신 필요`로 표시하고 새 CLI 기록 또는 계정 조회를 기다립니다.

문제를 재현할 때에는 `--diagnose` 출력, CLI 버전, 그리고 대화 내용을 제외한 오류 메시지를 함께 확인하는 것이 좋습니다.

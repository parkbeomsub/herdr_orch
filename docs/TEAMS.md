# 팀 프리셋 만들기

`config/teams/*.json` 하나가 팀 하나입니다. `dev.json`을 복사해 고치는 게 가장 빠릅니다.

```bash
cp ~/.config/herdr/orch/teams/dev.json ~/.config/herdr/orch/teams/myteam.json
orch --list-teams        # 목록에 나오면 인식된 것
orch 4 --team myteam
```

## 스키마

```jsonc
{
  "name": "팀 이름",                    // 필수 — 사람이 읽는 이름
  "cwd": "~/projects/foo",             // 선택 — 이 팀의 기본 작업 디렉토리
  "model": "참고한 조직 모델",           // 선택 — 메모용, 동작에 영향 없음
  "description": "이 팀이 무엇인가",      // orch 프롬프트에 들어감
  "flow": "A → B → C ‖ D는 병렬",       // 팀 전체 흐름. 전원 프롬프트에 들어감
  "guides": ["handoff.md"],            // 전원에게 주입할 가이드 (config/guides/)
  "roles": [ /* 아래 */ ]
}
```

### 역할 하나

```jsonc
{
  "name": "코어작가",                    // 필수 — 팬 라벨이 된다. 한글 가능
  "en": "core-writer",                 // 필수 — herdr agent 이름. [a-z][a-z0-9_-]{0,31}
  "brief": "한 줄 책임",                 // 필수 — --status·orch 프롬프트에 표시
  "prompt": "이 역할에게 줄 지시…",       // 필수 — 이게 실제 시스템 프롬프트
  "mcp": ["github", "context7"],       // 선택 — 권장 MCP (설치하지는 않음)
  "plugins": ["code-review@..."],      // 선택 — 권장 플러그인
  "ref_agents": ["backend-developer"], // 선택 — 참고할 공개 서브에이전트 정의
  "guides": ["no-ai-look.md"]          // 선택 — 이 역할에게만 추가로 줄 가이드
}
```

> **`en`은 반드시 소문자 슬러그**여야 합니다. herdr 0.7.5부터 agent 이름이
> `[a-z][a-z0-9_-]{0,31}` 로 제한되어 한글이 거부됩니다.
> 팬 라벨(`name`)은 한글이어도 됩니다 — `orch-msg`가 라벨로 대상을 찾습니다.

## 역할 **순서가 곧 우선순위**입니다

`orch 4 --team myteam` 은 **앞에서부터 4개**를 뽑습니다.
그래서 "4명만 띄웠을 때 누가 있어야 하는가"가 순서를 결정합니다.

`video` 프리셋을 예로 들면, 현재 순서는 프로듀서 → 작가 → 감독 → 비주얼생성이라
**4명이면 AI티검수가 안 들어갑니다.** 검수를 항상 포함하고 싶으면 위로 올리세요.
실제로 몇 명으로 돌릴지에 따라 이 순서가 가장 체감이 큽니다.

## `prompt` 작성 요령

프롬프트가 전부입니다. 나머지 필드는 부속입니다.

**되는 것**
- **판단 기준**을 준다 — "언제 되돌리고 언제 통과시키는가"
- **하지 말 것**을 명시한다 — 금지가 권장보다 잘 지켜집니다
- **산출물 위치**를 박는다 — `초안은 content/drafts/ 에 둔다`
- **다음 수령자**를 적는다 — 핸드오프가 흐려지는 게 가장 흔한 실패입니다

**안 되는 것**
- "최선을 다해라", "전문가처럼" 같은 말 — 아무 동작도 바꾸지 않습니다
- 다른 역할의 일까지 적기 — 그 역할의 프롬프트에 적으세요

검증 역할은 특히 **"통과시켜라"가 아니라 "틀린 곳을 찾아라"** 로 써야 작동합니다.
생성자에게 자기 검토를 시키면 거의 항상 통과시킵니다.

## 가이드 (`config/guides/`)

여러 역할이 공유하는 규칙은 가이드로 빼고 `guides` 배열로 주입합니다.
팀 전체(`루트의 guides`) + 역할별(`역할의 guides`)이 합쳐져 들어갑니다.

기본 제공:

| 가이드 | 내용 |
|---|---|
| `handoff.md` | 단일 오너 원칙, 명시적 핸드오프 — 전 팀 공통 |
| `comms.md` | `orch-msg` 사용법 — 자동 주입 |
| `no-ai-look.md` | AI 생성 티 제거 체크리스트 (영상·사진) |
| `platform-rules.md` | 소셜 채널별 운영 규칙 |

## 검증

```bash
jq . ~/.config/herdr/orch/teams/myteam.json     # JSON 문법
orch --list-teams                                # 인식되는가
orch 2 --team myteam --workspace <테스트WS> --dry-run 2>/dev/null || \
  ORCH_CLAUDE_CMD="echo X" orch 2 --team myteam --workspace <테스트WS>
```

`ORCH_CLAUDE_CMD="echo X"` 로 두면 claude 대신 echo가 실행되어
**실제 비용 없이 레이아웃과 프롬프트 생성만** 확인할 수 있습니다.
생성된 프롬프트는 `~/.config/herdr/orch/.runs/<랜덤>/` 에 있습니다.

숨김 워크스페이스를 만들어 테스트하고 지우면 깔끔합니다:

```bash
W=$(herdr workspace create --label __test --no-focus | jq -r '.result.workspace.workspace_id')
ORCH_CLAUDE_CMD="echo X" orch 3 --team myteam --workspace "$W"
herdr pane list --workspace "$W" | jq -r '.result.panes[] | "\(.pane_id) \(.label // "-")"'
herdr workspace close "$W"
```

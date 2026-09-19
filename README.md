# orch

**터미널에 AI 에이전트 팀을 띄우고, 오케스트레이터 하나가 그들을 부린다.**
[herdr](https://herdr.dev) 위에서 도는 얇은 bash 레이어 — 팀 프리셋, 팬 간 메시징, 워크스페이스 격리.

```bash
orch --doctor              # 설치가 제대로 됐는지 한 번에 점검
orch --show dev            # 어떤 역할이 들어있는지 먼저 본다
orch 4 --team dev          # 개발팀 4명 (PM·테크리드·디자이너·풀스택)
orch 4 --agent codex       # Claude Code 대신 Codex로
orch --status              # 누가 일하고 누가 막혔는지
orch --dashboard --serve   # 같은 걸 브라우저로, 실시간
orch --reharness           # 규칙을 바꿨다 → 대화는 유지한 채 하네스만 재구축
orch --stop                # 이 스페이스의 팀 정리
```

![demo](docs/demo.gif)

<sub>`orch 4 --team dev` 한 줄로 오케스트레이터 + 에이전트 4명이 뜨고, 지시를 받아 일을 시작합니다.<br>
GIF는 [`docs/demo.tape`](docs/demo.tape)로 렌더링됩니다 — `brew install vhs && vhs docs/demo.tape`</sub>

---

## 뭘 해결하나

에이전트를 하나 쓰는 건 쉽다. 아홉 개를 동시에 돌리는 순간 다른 문제가 생긴다.

| 문제 | orch가 하는 것 |
|---|---|
| 매번 역할 프롬프트를 손으로 붙여넣는다 | **팀 프리셋** — 역할·책임·가이드가 JSON 하나에 |
| 누가 멈췄는지 창을 하나씩 열어봐야 안다 | `orch --status` — 워크스페이스 단위 상태표 |
| 에이전트끼리 주고받은 게 어디에도 안 남는다 | `orch-msg` — 파일 로그가 진실 원본 |
| 스페이스 두 개를 띄우면 메시지가 남의 팀으로 간다 | **워크스페이스 격리** — pane_id 접두사로 강제 |
| 규칙을 고치면 팀을 새로 띄워야 한다 | `--reharness` — 맥락 유지한 채 프롬프트만 교체 |
| 팀 JSON 오타가 조용히 통과된다 | **실행 전 검증** — 빠진 `prompt`·잘못된 `en` 슬러그를 잡아냄 |
| 실수로 같은 스페이스에 팀을 두 번 만든다 | **중복 감지** — 라벨 충돌로 메시지가 엉키기 전에 막음 |

## 필요한 것

| | 버전·비고 |
|---|---|
| [herdr](https://herdr.dev) | 0.7.5+ · **Linux·macOS 안정, Windows는 프리뷰 베타** |
| [Claude Code](https://claude.com/claude-code) | `claude` 명령이 PATH에 |
| `bash` | 3.2+ (macOS 기본 포함) |
| `jq` | JSON 파싱 |

> **Windows 사용자는 [INSTALL.md](INSTALL.md#windows)를 먼저 읽으세요.**
> herdr Windows 빌드가 프리뷰라 **WSL2 경로를 권장**합니다.

## 설치

```bash
git clone https://github.com/parkbeomsub/herdr_orch.git
cd herdr_orch
./install.sh
```

`install.sh`가 하는 일은 두 가지뿐입니다 — `bin/*`를 PATH에 링크하고, `config/*`를 `~/.config/herdr/orch/`에 복사합니다. 기존 파일은 덮어쓰기 전에 물어봅니다.

OS별 상세는 [INSTALL.md](INSTALL.md)를 보세요.

## 5분 시작

```bash
herdr                                 # herdr 실행 (팬 안에서 아래를 친다)
orch                                  # 인자 없이 치면 용도·위키·모델을 물어봐준다
orch --list-teams                     # 어떤 팀이 있나
orch 4 --team dev --cwd ~/myproject   # 개발팀 4명을 내 프로젝트에서
```

왼쪽 50%에 **orch**(오케스트레이터), 오른쪽에 에이전트 4개가 뜹니다.
5개를 넘으면 새 탭에 3×3 그리드로 배치됩니다.

**orch 팬에만 말하세요.** 개별 에이전트에게 직접 지시하면 오케스트레이터가 누가 뭘 하는지 몰라 중복·누락이 생깁니다.

## 기본 팀 프리셋

업계 표준 조직 구조를 조사해 만들었습니다. 각 9역할이고, `N`을 주면 우선순위 순으로 잘라 씁니다.

| 프리셋 | 기반 | 최소 4인 구성 |
|---|---|---|
| `dev` | Spotify Squad / Amazon Two-Pizza | PM · 테크리드 · 디자이너 · 풀스택 |
| `marketing` | 수요창출25/콘텐츠20/옵스15 배분 | 총괄 · 퍼포먼스 · 콘텐츠 · 옵스 |
| `content` | 단일 에디터 승인 + 병렬 트랙 | 매니저 · 라이터 · SEO · 디자이너 |
| `video` | 프리/프로덕션/포스트 3단계 | 프로듀서 · 작가 · 감독 · 비주얼생성 |
| `growth` | Sean Ellis / Reforge 주간 실험 | 리드 · 분석가 · 엔지니어 · 마케터 |
| `analysis` | 분석 스쿼드 | 분석리드 · 데이터엔지니어 · 분석가 · 검증 |
| `planning` | Discovery Squad / 듀얼 트랙 | 기획리드 · 리서치 · 명세 · 비판 |
| `qa` | Quality Engineering / Shift-Left | QA리드 · 테스트설계 · 자동화 · 탐색 |

**`video`는 AI 팀에 맞게 각색했습니다.** 에이전트는 물리 촬영을 못 하므로 '촬영감독'을 '비주얼생성'으로 바꾸고, 실물 촬영팀에 없는 **AI티 검수** 역할을 최종 게이트로 넣었습니다.

### 직접 만들기

```bash
orch --new-team myteam          # 질문에 답하면 JSON이 생성됨
orch --new-team myteam --ai     # 역할 지시문 초안까지 AI가 작성
```

`--ai`는 팀 설명과 역할 목록을 보고 각 역할의 시스템 프롬프트를 씁니다. 예를 들어 "침투테스터"에게는 이런 게 나옵니다:

> 너는 정적분석 결과가 **틀린 곳을 찾는다** — 오탐(실제로는 도달 불가능한 경로)과 누락 양쪽을 모두 겨냥해라. 재현 가능한 PoC를 붙이지 못한 항목은 '악용 가능'이라고 쓰지 말고 **미검증으로 되돌린다.** 승인된 스코프 밖 자산은 건드리지 마라.

초안이므로 그대로 쓰지 말고 검토하세요. JSON을 직접 고쳐도 됩니다 — 스키마는 [docs/TEAMS.md](docs/TEAMS.md)에.

## 위키를 주면 팀을 짜줍니다

```bash
orch --wiki ~/myproject/docs                    # 한 곳
orch --wiki ~/docs --wiki ~/specs               # 여러 곳
orch --wiki ~/docs,~/specs,~/rfcs               # 쉼표도 가능
```

헤드리스 claude가 문서를 읽고 **이 프로젝트에 맞는 역할 구성을 JSON으로 뽑은 뒤** 그대로 팬을 만듭니다. 프리셋 하나에 안 맞으면 혼합 구성을 짭니다. 경로를 여러 개 주면 전부 훑습니다.

## Claude Code / Codex 둘 다 됩니다

```bash
orch 4 --team dev --agent codex
ORCH_AGENT=codex orch 4 --team dev     # 기본값으로 고정
```

두 CLI는 프롬프트 주입 방식이 근본적으로 다릅니다.

| | Claude Code | Codex |
|---|---|---|
| 시스템 프롬프트 | `--append-system-prompt` | **플래그 없음** — `AGENTS.md` 파일만 읽음 |
| 권한 우회 | `--dangerously-skip-permissions` | `--full-auto` |
| 재개 | `claude --resume <id>` | `codex resume <id>` |

Codex는 시스템 프롬프트 플래그가 없어서, 역할 지시문을 **`<cwd>/.orch/<역할>.md`에 두고 첫 메시지로 전달**합니다. 공용 `AGENTS.md`를 덮어쓰면 팬끼리 충돌하므로 역할별 파일을 따로 둡니다. 대화가 길어져도 에이전트가 그 파일을 다시 읽을 수 있습니다.

Codex 상태를 herdr 사이드바에 표시하려면 한 번만:

```bash
herdr integration install codex
```

## 단축키 — 팬·탭·스페이스 오가기

에이전트가 여러 개면 **이동이 가장 잦은 동작**입니다. 그래서 이동은 prefix 없이 바로,
가끔 쓰는 생성·이름변경은 prefix를 거치게 배치했습니다.

```bash
cp config/herdr-config.toml ~/.config/herdr/config.toml
herdr config check && herdr server reload-config     # ← 리로드해야 적용됩니다
```

prefix는 **`Ctrl+A`** 입니다 (GNU screen 스타일). 누르고 **뗀 뒤** 다음 키를 칩니다.

### 이동 — prefix 없이

| 대상 | 키 | 비고 |
|---|---|---|
| **팬** | `Ctrl` + `← ↑ ↓ →` | 수식키 하나. 가장 자주 씀 |
| **탭** | `Ctrl`+`Shift` + `← →` | 좌우 = 탭 |
| **스페이스**(워크스페이스) | `Ctrl`+`Shift` + `↑ ↓` | 상하 = 스페이스 |

방향이 일관됩니다 — **좌우는 탭, 상하는 스페이스**, 수식키가 하나면 팬입니다.

### 생성

| 대상 | 키 |
|---|---|
| 스페이스 | `Ctrl+A` `N` |
| 탭 | `Ctrl+A` `T` |
| 팬 — 위아래 분할 | `Ctrl+A` `-` |
| 팬 — 좌우 분할 | `Ctrl+A` `\` |

### 이름 변경

| 대상 | 키 |
|---|---|
| 스페이스 | `Ctrl+A` `Shift+I` |
| 탭 | `Ctrl+A` `Shift+T` |
| 팬 | `Ctrl+A` `Shift+N` |

> 팬 이름은 `orch-msg`가 대상을 찾는 **주소**입니다. 역할을 바꾸면 이름도 바꾸세요.
> 단축키로 바꾸면 herdr 내부의 `agent` 이름은 안 따라오므로, 역할 재배정이라면
> `herdr agent rename <pane_id> <영문슬러그>` 도 함께 하세요.

### 그 밖

| 동작 | 키 |
|---|---|
| 팬 닫기 | `Ctrl+A` `X` |
| 팬 확대/축소 | `Ctrl+A` `Z` |
| 사이드바 토글 | `Ctrl+A` `B` |
| 설정 열기 | `Ctrl+A` `S` |
| 디태치 (세션은 유지) | `Ctrl+A` `Q` |

### ⚠️ 안 먹히면 herdr가 아니라 터미널 문제입니다

터미널이 키를 먼저 가로채면 herdr까지 도달하지 않습니다. **무엇이 전달되는지 먼저 보세요:**

```bash
cat -v      # 키를 누르면 herdr가 받는 값이 그대로 찍힙니다. Ctrl+C 로 종료
```

| 출력 | 의미 |
|---|---|
| `^[[1;5D` | Ctrl+Left — 정상 전달 |
| `^[b` | **단어 이동으로 가로채짐** — 그 조합은 못 씀 |
| `^[[D` | 수식키가 무시됨 |
| (아무것도 없음) | OS·윈도우 매니저가 먹음 |

대표적인 함정 — iTerm2는 `Option+←/→`를 단어 이동으로 매핑해두고, `Option Key Sends = Normal`이면
**Option이 낀 조합 전체가 전송되지 않습니다.** GNOME은 `Ctrl+Alt+←/→`를 데스크톱 워크스페이스 전환에
선점합니다. OS·터미널별 해결법은 [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md)에 정리했습니다.

## 에이전트 간 통신

```bash
orch-msg send 코어작가 '초안 검토 부탁'   # 역할명(팬 라벨)으로
orch-msg log --last 30                   # 최근 대화
orch-msg who                             # 내 워크스페이스 팀원
```

**두 가지 설계 결정이 있습니다.**

첫째, **파일 로그가 진실 원본**입니다. 팬 전달은 상대가 작업 중이면 유실될 수 있어서, `<cwd>/comms/log.md`에 남는 기록을 정본으로 봅니다. 5MB를 넘으면 자동 회전합니다.

둘째, **워크스페이스를 절대 넘지 않습니다.** herdr가 모든 팬에 주입하는 `HERDR_WORKSPACE_ID`를 신원으로 쓰고, 대상이 다른 스페이스면 전송을 **거부**합니다. 포커스된 스페이스로 폴백하지 않습니다 — 신원을 모르면 보내지 않고 죽는 쪽이 맞습니다.

## `--reharness`

규칙(`CLAUDE.md`)이나 가이드를 고쳤을 때, 팀을 새로 띄우지 않고 하네스만 다시 세웁니다.

```bash
orch --reharness --dry-run   # 프롬프트만 재생성해서 확인
orch --reharness             # 각 팬을 --resume 으로 재기동
```

프로젝트의 `CLAUDE.md`와 최근 산출물 목록을 다시 읽어 시스템 프롬프트를 갱신하고, **대화 맥락은 `--resume`으로 유지**합니다. 팀 프리셋에 없는 역할(운영 중 추가된 것)도 공통 규칙을 받습니다.

## 한 워크스페이스에 팀 여럿

기획팀을 돌리다 개발팀이 필요해지면 새 탭에 띄우면 됩니다. 각 팀은 자체 오케스트레이터를 갖습니다.

```bash
orch 4 --add-team 개발              # 새 탭 'orch-dev' 에 개발팀
orch 4 --add-team qa --name 검증    # 탭 이름을 직접
```

한 오케가 20명을 넘게 관리하면 맥락이 터집니다. 팀마다 오케를 두고,
팀 간에는 **오케↔오케**로만 연락하게 했습니다. 남의 팀 에이전트에 직접 쓰면
그 팀 오케가 상황을 모르게 됩니다.

정리할 때는 대상을 지정합니다.

```bash
orch --stop                       # 포커스된 탭의 팀만
orch --stop --tab orch-qa         # 그 팀만
orch --stop --all-teams           # 전부
```

## 운영 중 에이전트 업그레이드

에이전트가 능력이 모자라 막혔을 때, 오케스트레이터가 스킬을 찾아 넣어줍니다.

```bash
orch skill find pdf                             # 후보 검색
orch skill add vercel-labs/skills --role 연구원  # 설치 + 그 역할만 재기동
orch skill list                                 # 설치된 목록
```

- 설치는 팀 작업 디렉토리의 `.claude/skills/` 로 **격리**됩니다. 전역을 오염시키지 않습니다
- `--role` 을 주면 그 팬만 `--resume` 으로 재기동하므로 **대화 맥락이 유지**됩니다
- 설치한 스킬은 팀 프리셋의 `skills` 배열에 기록돼, 다음에 같은 팀을 띄우면 자동으로 깔립니다

[vercel-labs/skills](https://github.com/vercel-labs/skills) 의 `npx skills` 를 씁니다.
없으면 `orch --doctor` 가 알려줍니다.

## 특정 역할만 다시 세우기

```bash
orch --reharness --only 연구원        # 한 역할만
orch --reharness --only 연구원,구현    # 여러 역할
orch --reharness --tab orch-qa        # 다른 탭의 팀을 대상으로
```

역할 이름은 한글 이름과 영문 슬러그 둘 다 받습니다.

## orch 자체를 관리하는 세션

```bash
orch --self
```

`setting` 워크스페이스에 orch 명령어 자체를 고도화·관리하는 세션을 하나 띄웁니다.
작업 디렉토리는 설정 디렉토리이고, 이미 떠 있으면 새로 만들지 않고 그 팬으로 이동합니다.

## 현황을 화면으로 — `orch --dashboard`

팬을 하나씩 열어보지 않고도 팀 전체가 지금 무엇을 하는지 한 장으로 본다.

```bash
orch --dashboard              # HTML 한 번 생성
orch --dashboard --serve      # http://localhost:7777 에 띄우고 2초마다 갱신
orch --dashboard --open       # 생성 후 브라우저로 열기
orch --dashboard --json       # 데이터만 (스크립트용)
```

보여주는 것:

| | |
|---|---|
| **메시지 흐름 그래프** | 오케스트레이터를 중심에 둔 방사형 — 선 굵기가 주고받은 메시지 수 |
| **에이전트 카드** | 역할별 상태(작업 중/대기/막힘)와 현재 작업 |
| **타임라인** | `comms/log.md` 의 최근 대화 |

데이터는 세 곳에서 직접 읽는다 — 별도 에이전트나 수집 데몬이 없다.

1. `state/<ws>.json` — 팀 편성
2. `herdr agent list` — 실시간 상태
3. `<cwd>/comms/log.md` — 메시지 기록

**라이브 데모 → https://parkbeomsub.github.io/herdr_orch/dashboard/**

생성된 HTML 은 외부 CDN 을 안 쓰는 단일 파일이라 그대로 공유해도 된다.
`orch --dashboard --demo` 는 샘플 데이터로 같은 화면을 만든다 — 팀이 안 떠 있어도 보인다.

## 세션 백업과 복구

재부팅 대비로 레이아웃과 claude 세션 ID 를 스냅샷해 둡니다.

```bash
orch-snapshot              # 스냅샷 (재부팅 전)
orch-snapshot --shutdown   # 스냅샷 + herdr 정상 종료
orch-snapshot --verify     # 재부팅 후 복원 결과 대조
```

herdr 자체도 `resume_agents_on_restore` 로 복원을 시도하지만, 달라진 경우를 위해
역할↔세션ID 표와 `claude --resume` 명령을 대장으로 남깁니다.

## 안 하는 것

- **소셜·외부 계정에 아무것도 게시하지 않습니다.** 원고를 만들 뿐입니다.
- **MCP·플러그인을 임의로 설치하지 않습니다.** 인증·과금이 걸리므로 명령어만 제안합니다.
- **`herdr pane run`·`pane close`는 권한 허용 목록에서 일부러 뺐습니다.** 새 에이전트 생성과 팬 삭제에는 승인이 남습니다 — 의도된 안전장치입니다.

## 비용 주의

Anthropic 공식 자료 기준 **멀티에이전트는 일반 채팅 대비 약 15배 토큰**을 씁니다(단일 에이전트 ~4배).
에이전트 수는 *가진 도구의 수용량*이 아니라 **실제로 병렬화 가능한 작업 수**에 맞추세요. 4개로 시작해 병목이 보일 때 늘리는 편이 거의 항상 낫습니다.

순차 의존인 작업(A가 끝나야 B가 시작)은 멀티에이전트로 나눠도 이득이 없습니다.

## 문서

- [INSTALL.md](INSTALL.md) — OS별 설치 (Windows·Linux·macOS)
- [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) — 단축키 전체 + OS·터미널별 함정 해결
- [docs/TEAMS.md](docs/TEAMS.md) — 팀 프리셋 스키마
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — 안 될 때
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 어떻게 도는가

## 라이선스

MIT. herdr와 Claude Code는 각자의 라이선스를 따릅니다 — 이 저장소는 그 위에서 도는 스크립트만 담고 있고, 두 프로젝트와 제휴 관계가 없습니다.

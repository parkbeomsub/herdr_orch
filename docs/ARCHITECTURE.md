# 어떻게 도는가

`orch`는 herdr 위의 얇은 층입니다. **새로운 런타임을 만들지 않고** herdr의 팬·상태·API를 씁니다.

```
┌─ herdr 서버 (PTY를 붙들고 있음, 클라이언트 닫아도 유지) ─────────┐
│                                                                │
│  워크스페이스 wA                    워크스페이스 wB              │
│  ┌──────────┬──────────┐          ┌──────────┬──────────┐      │
│  │  orch    │ 편집장    │          │  orch    │ 백엔드    │      │
│  │ wA:p2    │ wA:p3    │          │ wB:p2    │ wB:p3    │      │
│  │          ├──────────┤          │          ├──────────┤      │
│  │          │ 작가      │          │          │ QA       │      │
│  │          │ wA:p4    │          │          │ wB:p4    │      │
│  └──────────┴──────────┘          └──────────┴──────────┘      │
│         ↑ 서로 절대 통신하지 않는다 ↑                            │
└────────────────────────────────────────────────────────────────┘
```

각 팬은 **독립 프로세스에 독립 컨텍스트 윈도우**입니다. 서로의 메모리를 못 봅니다.
그래서 공유 상태는 **파일**로만 지속됩니다 — 이게 `orch-msg`가 로그 파일을 정본으로 두는 이유입니다.

## 생성 흐름

```
orch 4 --team dev
  │
  ├─ 팀 스펙 로드          config/teams/dev.json
  ├─ 탭 생성               herdr tab create --workspace $WS
  ├─ 팬 분할               좌 50% orch + 우측 4스택 (5개 이상이면 새 탭 3×3)
  ├─ 프롬프트 생성          .runs/<랜덤>/{orch,agent-N}.md
  │    agent.md + 역할 prompt + 가이드 + CLAUDE.md + 최근 산출물
  ├─ claude 실행           herdr pane run "<env> claude --append-system-prompt ..."
  ├─ 라벨·이름 등록         pane rename(한글) + agent rename(영문 슬러그)
  └─ 상태 저장             state/<WS>.json
```

## 신원은 런타임에서 받는다

각 팬은 자기가 누구인지를 **환경변수**로 압니다. 프롬프트에도 넣지만, 프롬프트는
대화가 길어지면 잊히거나 오염됩니다.

| 변수 | 출처 | 특징 |
|---|---|---|
| `HERDR_WORKSPACE_ID` | **herdr가 주입** | 재시작해도 살아 있음. 격리의 근거 |
| `HERDR_PANE_ID` | **herdr가 주입** | 〃 |
| `ORCH_ROLE` | orch가 주입 | 역할명 (herdr는 모름) |
| `ORCH_LOG` | orch가 주입 | 통신 로그 경로 |

**격리는 `HERDR_WORKSPACE_ID`에 걸려 있습니다.** orch가 넣은 값이 유실돼도 herdr 것은 남으므로,
resume 후에도, 수동으로 띄운 팬에서도 경계가 유지됩니다.

## 워크스페이스 격리

세 겹입니다.

1. **조회** — `herdr pane list --workspace $WS`. 애초에 다른 스페이스를 안 봅니다
2. **필터** — `agent list`는 전역을 반환하므로 `workspace_id == $WS`로 거릅니다
3. **실행 직전** — 대상 pane_id가 `$WS:`로 시작하는지 **매 건** 확인, 아니면 중단

> **왜 이렇게까지 하나**: `herdr agent send <이름>`은 이름을 **herdr 전역에서** 해석합니다.
> 두 스페이스에 `편집장`이 있으면 어느 쪽으로 갈지 정의돼 있지 않습니다.
> `pane_id`는 `wA:p3`처럼 워크스페이스가 접두사라 구조적으로 안전합니다.

## 메시지 전달

```
orch-msg send 편집장 '내용'
  │
  ├─ $WS 안에서 팬 라벨로 pane_id 해소   (여러 개 걸리면 거부)
  ├─ 경계 확인                          ($WS: 로 시작하나)
  ├─ escape → ctrl+u                    잔여 입력 제거
  ├─ send-text                          입력만 됨
  ├─ 2초 대기 → enter                   ← 이게 없으면 제출 안 됨
  ├─ 미제출이면 enter 재시도
  └─ comms/log.md 에 기록                ← 진실 원본
```

**`agent send`의 반환값 `ok`는 전달 성공이 아닙니다.** 입력 자체가 성공했다는 뜻입니다.
제출을 안 하면 다음 메시지와 합쳐져 한 덩어리로 갑니다. 그래서 로그가 정본입니다.

## `--reharness`

팀을 새로 만들지 않고 하네스만 다시 세웁니다.

```
orch --reharness
  │
  ├─ state/<WS>.json 에서 team·cwd 복원
  ├─ 현재 팬 라벨 ↔ 팀 역할 매칭
  │    프리셋에 없는 라벨도 포함 (운영 중 추가된 역할)
  ├─ 프롬프트 재생성  (CLAUDE.md·가이드·최근 산출물 다시 읽음)
  ├─ agent_session 조회 → --resume 대상 결정
  └─ ctrl+c → claude --resume <세션> --append-system-prompt <새 프롬프트>
```

대화 맥락은 유지되고 시스템 프롬프트만 교체됩니다.
프롬프트 끝에 *"충돌하면 위(새 규칙)를 따른다"* 를 넣어 우선순위를 명시합니다.

## Agent Teams와의 층 분리

Claude Code의 in-process 팀원(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`)은 **다른 층**입니다.

| | herdr 팬 | Agent Teams |
|---|---|---|
| 보이는가 | 사이드바·`--status`에 보임 | **안 보임** |
| `/resume` | 복원됨 | **복원 안 됨** |
| 중첩 | 가능 | 불가 |
| 쓸 곳 | 수명이 긴 역할 | 한 턴 안에 닫히는 병렬 작업 |

`orch`는 자기가 띄운 팬에만 이 환경변수를 넣습니다 — 전역 `settings.json`은 건드리지 않으므로
수동 운영 중인 다른 워크스페이스는 영향받지 않습니다.

## 파일이 놓이는 곳

```
~/.config/herdr/orch/
├── orchestrator.md     orch 공통 프롬프트
├── agent.md            에이전트 공통 프롬프트
├── planner.md          --wiki 분석용
├── teams/*.json        팀 프리셋
├── guides/*.md         공유 규칙
├── .runs/<랜덤>/       생성된 프롬프트 (커밋 금지)
└── state/<WS>.json     워크스페이스별 팀 상태 (커밋 금지)

<프로젝트>/comms/log.md  에이전트 간 통신 기록 (5MB 초과 시 회전)
```

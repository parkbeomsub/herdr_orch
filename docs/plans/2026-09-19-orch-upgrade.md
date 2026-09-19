# orch 고도화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** orch에 대화형 진입, 운영 중 스킬 자동 주입, 한 워크스페이스 내 다중 팀 증설을 추가한다.

**Architecture:** 968줄 단일 bash 스크립트에서 state 처리·스킬 설치·마법사를 `lib/*.sh`로 분리하고 `orch`가 source한다. state를 워크스페이스당 팀 1개(v1)에서 팀 배열(v2)로 올리는 것이 나머지 전부의 토대다. 기존 `--reharness`(세션 resume 재기동)를 재사용해 스킬 주입 시 대화 맥락을 보존한다.

**Tech Stack:** bash 3.2, jq, herdr CLI, npx skills (vercel-labs/skills)

**Spec:** `~/.config/herdr/orch/docs/2026-09-19-orch-upgrade-design.md`

## Global Constraints

- **bash 3.2** (macOS 기본). 연관배열(`declare -A`) 사용 금지. `mapfile`/`readarray` 없음
- **`set -euo pipefail`** 하에서 동작. 블록 **마지막 줄**에 `[ -n "$X" ] && printf` 를 쓰면 X가 빌 때 스크립트가 죽는다 — 반드시 `if` 문으로 쓴다
- 모든 사용자 대면 메시지는 **한국어**
- 기존 플래그 인터페이스는 **불변**. 새 기능은 추가이지 대체가 아니다 (유일한 예외: `--stop` 범위 축소, Task 3에서 경고 문구로 명시)
- 스킬 설치는 **에이전트 cwd의 `.claude/skills/`** 에만. `npx skills add -g` 금지
- state 파일 경로: `~/.config/herdr/orch/state/<workspace_id>.json`
- 팀 간 통신은 **오케↔오케** 만
- jq 출력으로 JSON을 만든다. `printf` 로 JSON 문자열을 조립하지 않는다 (기존 orch:948-964 방식은 따옴표·개행 이스케이프에 취약)

---

## File Structure

| 파일 | 책임 | 상태 |
|---|---|---|
| `lib/state.sh` | state v1→v2 승격, 팀 조회/추가/삭제 | 신규 |
| `lib/skills.sh` | `npx skills` 래퍼, 설치 경로 검증 | 신규 |
| `lib/wizard.sh` | 대화형 마법사, 답변→플래그 번역 | 신규 |
| `tests/run.sh` | 테스트 러너 | 신규 |
| `tests/test_*.sh` | 테스트 케이스 | 신규 |
| `orch` | 인자 파싱, 팬 배치, 서브커맨드 라우팅 | 수정 |
| `teams/{analysis,planning,qa}.json` | 신규 프리셋 | 신규 |

`lib/*.sh` 는 herdr 를 직접 호출하지 않는 순수 함수를 우선한다. herdr 호출이 필요한 함수는 명령 문자열을 변수로 받아 테스트에서 스텁으로 치환할 수 있게 한다.

---

### Task 0: 테스트 하네스와 버전 관리

**Files:**
- Create: `~/.config/herdr/orch/tests/run.sh`
- Create: `~/.config/herdr/orch/tests/helpers.sh`
- Create: `~/.config/herdr/orch/.gitignore`

**Interfaces:**
- Produces: `assert_eq <expected> <actual> <label>`, `assert_contains <haystack> <needle> <label>`, `assert_fail <command> <label>` — 이후 모든 테스트가 쓴다. `run.sh` 는 `tests/test_*.sh` 를 전부 실행하고 실패가 하나라도 있으면 exit 1

- [ ] **Step 1: git 저장소 초기화와 .gitignore**

`~/.config/herdr/orch` 는 아직 git 저장소가 아니다. 커밋 단위로 진행하려면 먼저 만든다.

```bash
cd ~/.config/herdr/orch
git init
cat > .gitignore <<'EOF'
.runs/
state/
*.bak
EOF
git add -A
git commit -m "chore: orch 설정 디렉토리 버전 관리 시작"
```

`state/` 는 런타임 상태라 제외한다. `.runs/` 는 생성된 프롬프트라 제외한다.

- [ ] **Step 2: 어서션 헬퍼 작성**

```bash
cat > ~/.config/herdr/orch/tests/helpers.sh <<'EOF'
#!/bin/bash
# 테스트 어서션. bash 3.2 호환.
TESTS_RUN=0
TESTS_FAIL=0

assert_eq() { # <expected> <actual> <label>
  TESTS_RUN=$((TESTS_RUN+1))
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    TESTS_FAIL=$((TESTS_FAIL+1))
    printf '  FAIL %s\n       기대: %s\n       실제: %s\n' "$3" "$1" "$2"
  fi
}

assert_contains() { # <haystack> <needle> <label>
  TESTS_RUN=$((TESTS_RUN+1))
  case "$1" in
    *"$2"*) printf '  ok   %s\n' "$3" ;;
    *) TESTS_FAIL=$((TESTS_FAIL+1))
       printf '  FAIL %s\n       "%s" 안에 "%s" 가 없음\n' "$3" "$1" "$2" ;;
  esac
}

assert_fail() { # <label> <command...>  — 명령이 0이 아닌 코드로 끝나야 통과
  local label="$1"; shift
  TESTS_RUN=$((TESTS_RUN+1))
  if "$@" >/dev/null 2>&1; then
    TESTS_FAIL=$((TESTS_FAIL+1))
    printf '  FAIL %s (성공하면 안 되는데 성공함)\n' "$label"
  else
    printf '  ok   %s\n' "$label"
  fi
}

summary() {
  printf '\n%d개 중 %d개 실패\n' "$TESTS_RUN" "$TESTS_FAIL"
  [ "$TESTS_FAIL" -eq 0 ]
}
EOF
chmod +x ~/.config/herdr/orch/tests/helpers.sh
```

- [ ] **Step 3: 러너 작성**

```bash
cat > ~/.config/herdr/orch/tests/run.sh <<'EOF'
#!/bin/bash
# 모든 test_*.sh 를 실행한다. 하나라도 실패하면 1로 끝난다.
cd "$(dirname "$0")" || exit 1
fail=0
for t in test_*.sh; do
  [ -f "$t" ] || continue
  printf '\n== %s ==\n' "$t"
  bash "$t" || fail=1
done
exit "$fail"
EOF
chmod +x ~/.config/herdr/orch/tests/run.sh
```

- [ ] **Step 4: 하네스 자체를 검증하는 테스트**

```bash
cat > ~/.config/herdr/orch/tests/test_harness.sh <<'EOF'
#!/bin/bash
. "$(dirname "$0")/helpers.sh"
assert_eq "a" "a" "같은 문자열은 통과한다"
assert_contains "hello world" "world" "부분 문자열을 찾는다"
assert_fail "없는 명령은 실패한다" false
summary
EOF
bash ~/.config/herdr/orch/tests/run.sh
```

Expected: `3개 중 0개 실패`, exit 0

- [ ] **Step 5: 커밋**

```bash
cd ~/.config/herdr/orch
git add tests/
git commit -m "test: bash 테스트 하네스 추가"
```

---

### Task 1: state v2 스키마와 v1 승격

**Files:**
- Create: `~/.config/herdr/orch/lib/state.sh`
- Create: `~/.config/herdr/orch/tests/test_state.sh`

**Interfaces:**
- Consumes: Task 0의 `assert_eq`, `assert_contains`, `summary`
- Produces:
  - `state_migrate <v1_json>` → stdout에 v2 JSON. 이미 v2면 그대로 통과
  - `state_load <state_file>` → stdout에 v2 JSON. 파일 없으면 빈 골격 `{"version":2,"workspace":"","teams":[]}`
  - `state_save <state_file> <v2_json>` → 파일에 기록 (디렉토리 자동 생성)
  - `state_team_by_tab <v2_json> <tab_id>` → 해당 팀 객체 또는 빈 문자열
  - `state_upsert_team <v2_json> <team_json>` → 같은 `tab` 이면 교체, 없으면 추가한 v2 JSON
  - `state_remove_team <v2_json> <tab_id>` → 해당 팀을 뺀 v2 JSON

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > ~/.config/herdr/orch/tests/test_state.sh <<'EOF'
#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(dirname "$0")/../lib/state.sh"

V1='{"workspace":"w1J","team":"dev","cwd":"/tmp/x","spec":"/s.json",
     "orch_pane":"w1J:p2","model":"opus","lead_model":"claude-opus-5[1m]",
     "created":"2026-09-07T22:34:05",
     "roles":[{"idx":0,"name":"PM","slug":"pm","pane":"w1J:p3"}]}'

OUT=$(state_migrate "$V1")
assert_eq "2" "$(printf '%s' "$OUT" | jq -r '.version')" "v1을 승격하면 version이 2다"
assert_eq "w1J" "$(printf '%s' "$OUT" | jq -r '.workspace')" "워크스페이스가 보존된다"
assert_eq "1" "$(printf '%s' "$OUT" | jq -r '.teams | length')" "팀이 하나 생긴다"
assert_eq "dev" "$(printf '%s' "$OUT" | jq -r '.teams[0].team')" "팀 이름이 옮겨진다"
assert_eq "w1J:p2" "$(printf '%s' "$OUT" | jq -r '.teams[0].orch_pane')" "오케 팬이 옮겨진다"
assert_eq "w1J:t2" "$(printf '%s' "$OUT" | jq -r '.teams[0].tab')" "탭은 오케 팬 번호로 역산한다"
assert_eq "PM" "$(printf '%s' "$OUT" | jq -r '.teams[0].roles[0].name')" "역할이 보존된다"

AGAIN=$(state_migrate "$OUT")
assert_eq "$(printf '%s' "$OUT" | jq -S .)" "$(printf '%s' "$AGAIN" | jq -S .)" "승격은 멱등이다"

T2='{"tab":"w1J:t9","tab_label":"orch-qa","team":"qa","cwd":"/tmp/y",
     "orch_pane":"w1J:p20","model":"opus","lead_model":"l","created":"x","roles":[]}'
TWO=$(state_upsert_team "$OUT" "$T2")
assert_eq "2" "$(printf '%s' "$TWO" | jq -r '.teams | length')" "팀을 추가하면 2개가 된다"
assert_eq "qa" "$(printf '%s' "$(state_team_by_tab "$TWO" "w1J:t9")" | jq -r '.team')" "탭으로 팀을 찾는다"
assert_eq "dev" "$(printf '%s' "$(state_team_by_tab "$TWO" "w1J:t2")" | jq -r '.team')" "기존 팀도 그대로 찾힌다"
assert_eq "" "$(state_team_by_tab "$TWO" "w1J:t99")" "없는 탭은 빈 문자열이다"

DUP=$(state_upsert_team "$TWO" "$T2")
assert_eq "2" "$(printf '%s' "$DUP" | jq -r '.teams | length')" "같은 탭을 다시 넣으면 교체된다"

GONE=$(state_remove_team "$TWO" "w1J:t2")
assert_eq "1" "$(printf '%s' "$GONE" | jq -r '.teams | length')" "팀을 지우면 1개가 된다"
assert_eq "qa" "$(printf '%s' "$GONE" | jq -r '.teams[0].team')" "남은 팀이 맞다"

TMP=$(mktemp -d)
assert_eq "2" "$(state_load "$TMP/none.json" | jq -r '.version')" "없는 파일은 빈 v2 골격을 준다"
assert_eq "0" "$(state_load "$TMP/none.json" | jq -r '.teams | length')" "빈 골격의 팀은 0개다"
state_save "$TMP/s.json" "$TWO"
assert_eq "2" "$(state_load "$TMP/s.json" | jq -r '.teams | length')" "저장한 걸 다시 읽는다"
printf '%s' "$V1" > "$TMP/old.json"
assert_eq "2" "$(state_load "$TMP/old.json" | jq -r '.version')" "구형 파일을 읽으면 승격된다"
rm -rf "$TMP"

summary
EOF
```

- [ ] **Step 2: 실패 확인**

Run: `bash ~/.config/herdr/orch/tests/test_state.sh`
Expected: FAIL — `lib/state.sh: No such file or directory`

- [ ] **Step 3: 구현**

```bash
mkdir -p ~/.config/herdr/orch/lib
cat > ~/.config/herdr/orch/lib/state.sh <<'EOF'
#!/bin/bash
# orch state 처리. v1(워크스페이스당 팀 1개) → v2(팀 배열) 승격을 포함한다.
# 순수 함수만 둔다 — herdr 를 호출하지 않으므로 테스트에서 그대로 쓸 수 있다.

# v1 을 v2 로 올린다. 이미 v2 면 그대로 돌려준다. 멱등.
state_migrate() { # <json>
  printf '%s' "$1" | jq '
    if (.version? // 0) >= 2 then .
    else
      # 탭 ID 는 오케 팬 번호로 역산한다. v1 에는 탭 정보가 없고,
      # orch 가 만드는 첫 탭의 root 팬이 곧 오케 팬이기 때문에 이 대응이 성립한다.
      (.orch_pane // "") as $op
      | ($op | split(":") | if length == 2 then .[0] else "" end) as $ws
      | ($op | split(":p") | if length == 2 then .[1] else "" end) as $pn
      | {
          version: 2,
          workspace: (.workspace // $ws),
          teams: (if $op == "" then [] else [{
            tab: (if $ws != "" and $pn != "" then ($ws + ":t" + $pn) else "" end),
            tab_label: "orch",
            team: (.team // ""),
            cwd: (.cwd // ""),
            spec: (.spec // ""),
            orch_pane: $op,
            model: (.model // ""),
            lead_model: (.lead_model // ""),
            created: (.created // ""),
            roles: (.roles // [])
          }] end)
        }
    end'
}

# 파일을 읽어 v2 로 돌려준다. 없으면 빈 골격.
state_load() { # <state_file>
  if [ ! -f "$1" ]; then
    printf '{"version":2,"workspace":"","teams":[]}'
    return 0
  fi
  if ! jq -e . "$1" >/dev/null 2>&1; then
    # 깨진 파일은 조용히 버리지 않는다 — 백업하고 빈 골격으로 간다
    cp "$1" "$1.bak" 2>/dev/null || true
    printf '깨진 상태 파일을 %s.bak 으로 옮기고 새로 시작합니다\n' "$1" >&2
    printf '{"version":2,"workspace":"","teams":[]}'
    return 0
  fi
  state_migrate "$(cat "$1")"
}

state_save() { # <state_file> <v2_json>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" | jq . > "$1"
}

state_team_by_tab() { # <v2_json> <tab_id>  → 팀 객체 또는 빈 문자열
  printf '%s' "$1" | jq -c --arg t "$2" '.teams[] | select(.tab == $t)' 2>/dev/null
}

state_upsert_team() { # <v2_json> <team_json>  → 갱신된 v2 JSON
  printf '%s' "$1" | jq --argjson new "$2" '
    .teams = ((.teams // []) | map(select(.tab != $new.tab)) + [$new])'
}

state_remove_team() { # <v2_json> <tab_id>  → 갱신된 v2 JSON
  printf '%s' "$1" | jq --arg t "$2" '.teams = ((.teams // []) | map(select(.tab != $t)))'
}
EOF
```

- [ ] **Step 4: 통과 확인**

Run: `bash ~/.config/herdr/orch/tests/run.sh`
Expected: 모든 어서션 통과, exit 0

- [ ] **Step 5: 실제 구형 파일 5개로 승격 검증**

읽기 전용으로 확인한다. 원본은 건드리지 않는다.

```bash
for f in ~/.config/herdr/orch/state/*.json; do
  printf '%-10s ' "$(basename "$f")"
  ( . ~/.config/herdr/orch/lib/state.sh
    state_load "$f" | jq -r '"v\(.version) 팀\(.teams|length)개 \(.teams[0].tab // "-") \(.teams[0].team // "-")"' )
done
```

Expected: 5개 파일 모두 `v2 팀1개 <ws>:t<n> <팀명>` 형태. 에러 없음

- [ ] **Step 6: 커밋**

```bash
cd ~/.config/herdr/orch
git add lib/state.sh tests/test_state.sh
git commit -m "feat: state v2 스키마와 v1 자동 승격"
```

---

### Task 2: 팀 선택 규칙

**Files:**
- Modify: `~/.config/herdr/orch/lib/state.sh` (함수 추가)
- Create: `~/.config/herdr/orch/tests/test_select.sh`

**Interfaces:**
- Consumes: Task 1의 `state_team_by_tab`
- Produces: `state_select_team <v2_json> <focused_tab> <explicit_tab>` → 선택된 팀 객체를 stdout으로, 모호하면 빈 문자열과 함께 exit 2, 팀이 없으면 exit 1

선택 순서는 스펙 그대로다. ① `--tab` 명시 → ② 포커스 탭 → ③ 팀이 하나뿐이면 그것 → ④ 여러 개면 모호(exit 2).

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > ~/.config/herdr/orch/tests/test_select.sh <<'EOF'
#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(dirname "$0")/../lib/state.sh"

ONE='{"version":2,"workspace":"w1","teams":[
  {"tab":"w1:t2","tab_label":"orch","team":"dev","orch_pane":"w1:p2","roles":[]}]}'
TWO='{"version":2,"workspace":"w1","teams":[
  {"tab":"w1:t2","tab_label":"orch","team":"dev","orch_pane":"w1:p2","roles":[]},
  {"tab":"w1:t9","tab_label":"orch-qa","team":"qa","orch_pane":"w1:p20","roles":[]}]}'
NONE='{"version":2,"workspace":"w1","teams":[]}'

R=$(state_select_team "$TWO" "w1:t2" "w1:t9")
assert_eq "qa" "$(printf '%s' "$R" | jq -r '.team')" "명시한 탭이 포커스보다 우선한다"

R=$(state_select_team "$TWO" "w1:t9" "")
assert_eq "qa" "$(printf '%s' "$R" | jq -r '.team')" "명시가 없으면 포커스 탭을 쓴다"

R=$(state_select_team "$ONE" "w1:t99" "")
assert_eq "dev" "$(printf '%s' "$R" | jq -r '.team')" "팀이 하나면 포커스가 어긋나도 그것을 쓴다"

state_select_team "$TWO" "w1:t99" "" >/dev/null 2>&1
assert_eq "2" "$?" "여러 팀인데 포커스가 어긋나면 모호로 exit 2"

state_select_team "$NONE" "w1:t2" "" >/dev/null 2>&1
assert_eq "1" "$?" "팀이 없으면 exit 1"

state_select_team "$TWO" "" "w1:t404" >/dev/null 2>&1
assert_eq "1" "$?" "명시한 탭에 팀이 없으면 exit 1"

summary
EOF
```

- [ ] **Step 2: 실패 확인**

Run: `bash ~/.config/herdr/orch/tests/test_select.sh`
Expected: FAIL — `state_select_team: command not found`

- [ ] **Step 3: 구현**

`lib/state.sh` 끝에 덧붙인다.

```bash
cat >> ~/.config/herdr/orch/lib/state.sh <<'EOF'

# 대상 팀을 고른다.
#   exit 0 = 팀 객체를 stdout 으로
#   exit 1 = 팀이 없음
#   exit 2 = 여러 팀 중 고를 수 없음 (호출부가 목록을 보여주고 중단해야 한다)
state_select_team() { # <v2_json> <focused_tab> <explicit_tab>
  local js="$1" focus="$2" want="$3" n hit
  n=$(printf '%s' "$js" | jq -r '(.teams // []) | length')
  [ "$n" -gt 0 ] || return 1

  if [ -n "$want" ]; then
    hit=$(state_team_by_tab "$js" "$want")
    if [ -n "$hit" ]; then printf '%s' "$hit"; return 0; fi
    return 1
  fi

  if [ -n "$focus" ]; then
    hit=$(state_team_by_tab "$js" "$focus")
    if [ -n "$hit" ]; then printf '%s' "$hit"; return 0; fi
  fi

  if [ "$n" -eq 1 ]; then
    printf '%s' "$(printf '%s' "$js" | jq -c '.teams[0]')"
    return 0
  fi
  return 2
}

# 모호할 때 사용자에게 보여줄 목록
state_team_menu() { # <v2_json>
  printf '%s' "$1" | jq -r '(.teams // [])[] | "  \(.tab)\t\(.tab_label // "-")\t\(.team // "-")\t오케 \(.orch_pane)"'
}
EOF
```

- [ ] **Step 4: 통과 확인**

Run: `bash ~/.config/herdr/orch/tests/run.sh`
Expected: 전부 통과

- [ ] **Step 5: 커밋**

```bash
cd ~/.config/herdr/orch
git add lib/state.sh tests/test_select.sh
git commit -m "feat: 탭 기준 팀 선택 규칙"
```

---

### Task 3: orch 본체를 state v2 로 전환

**Files:**
- Modify: `/opt/homebrew/bin/orch` (상단 source 추가, `--stop` 블록 455-470, `--reharness` 로드 481-485, 상태 저장 944-968)

**Interfaces:**
- Consumes: Task 1·2 전부
- Produces: `--tab <label|id>`, `--all-teams` 플래그. `ORCH_STATE_JSON` (로드된 v2 JSON), `ORCH_TEAM_JSON` (선택된 팀) 전역 변수

- [ ] **Step 1: 백업과 lib 로드**

```bash
cp /opt/homebrew/bin/orch ~/.config/herdr/orch/orch.bak.$(date +%Y%m%d)
```

`PROMPT_DIR` 정의 직후(orch:57 부근)에 삽입한다.

```bash
# lib 로드 — state 처리는 여기서만 한다
. "$PROMPT_DIR/lib/state.sh"
```

- [ ] **Step 2: 플래그 추가**

인자 파싱 case 문(orch:89-126)에 두 줄을 추가한다. `--stop` 바로 위에 둔다.

```bash
    --tab) WANT_TAB="$2"; shift 2 ;;
    --all-teams) ALL_TEAMS=1; shift ;;
```

변수 초기화는 `STOP=""` 근처에 둔다.

```bash
WANT_TAB=""
ALL_TEAMS=""
```

- [ ] **Step 3: 포커스 탭을 알아내는 헬퍼**

`STATE_FILE` 정의 직후에 둔다. `--tab` 에 라벨을 줘도 탭 ID로 바꿔준다.

```bash
# 현재 포커스된 탭 ID. 못 구하면 빈 문자열.
focused_tab() {
  herdr tab list --workspace "$WS" 2>/dev/null \
    | jq -r '.result.tabs[]? | select(.focused == true) | .tab_id' | head -1
}

# 라벨이든 ID든 탭 ID로 정규화한다
resolve_tab() { # <label|tab_id>
  case "$1" in
    "$WS":t*) printf '%s' "$1"; return 0 ;;
  esac
  herdr tab list --workspace "$WS" 2>/dev/null \
    | jq -r --arg l "$1" '.result.tabs[]? | select((.label // "") == $l) | .tab_id' | head -1
}
```

- [ ] **Step 4: `--stop` 을 팀 단위로 좁힌다**

orch:454-471 블록 전체를 교체한다. 기존은 워크스페이스의 label 팬을 전부 닫았다.

```bash
if [ -n "$STOP" ]; then
  ORCH_STATE_JSON=$(state_load "$STATE_FILE")
  if [ -n "$ALL_TEAMS" ]; then
    echo "workspace $WS 의 orch 팀 전체 정리"
    TARGET_PANES=$(printf '%s' "$ORCH_STATE_JSON" \
      | jq -r '(.teams // [])[] | .orch_pane, (.roles[]?.pane)')
  else
    FT=$(focused_tab)
    WT=""
    if [ -n "$WANT_TAB" ]; then WT=$(resolve_tab "$WANT_TAB"); fi
    set +e
    ORCH_TEAM_JSON=$(state_select_team "$ORCH_STATE_JSON" "$FT" "$WT")
    rc=$?
    set -e
    if [ "$rc" -eq 1 ]; then echo "정리할 팀이 없습니다 (상태 파일: $STATE_FILE)"; exit 0; fi
    if [ "$rc" -eq 2 ]; then
      echo "이 워크스페이스에 팀이 여러 개입니다. --tab 으로 지정하거나 --all-teams 를 쓰세요:" >&2
      state_team_menu "$ORCH_STATE_JSON" | column -t -s "$(printf '\t')" >&2
      exit 1
    fi
    echo "팀 정리: $(printf '%s' "$ORCH_TEAM_JSON" | jq -r '"\(.tab_label // .tab) (\(.team // "커스텀"))"')"
    echo "(워크스페이스 전체가 아니라 이 탭의 팀만 닫습니다. 전체는 --all-teams)"
    TARGET_PANES=$(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.orch_pane, (.roles[]?.pane)')
  fi

  if [ -z "$TARGET_PANES" ]; then echo "  정리할 팬이 없습니다."; exit 0; fi
  printf '%s\n' "$TARGET_PANES" | sed 's/^/  /'
  if [ -z "$FORCE" ]; then
    printf '\n위 팬들을 닫습니다. 진행할까요? [y/N] '
    read -r _a </dev/tty || _a=n
    case "$_a" in [yY]*) ;; *) echo "취소했습니다."; exit 0 ;; esac
  fi
  printf '%s\n' "$TARGET_PANES" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in "$WS":*) herdr pane close "$p" >/dev/null 2>&1 && echo "  닫음: $p" ;;
                 *) echo "  경계 위반으로 건너뜀: $p" >&2 ;; esac
  done

  if [ -n "$ALL_TEAMS" ]; then
    rm -f "$STATE_FILE"
    echo "완료. 상태 파일도 지웠습니다."
  else
    TAB_GONE=$(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.tab')
    state_save "$STATE_FILE" "$(state_remove_team "$ORCH_STATE_JSON" "$TAB_GONE")"
    echo "완료. 상태에서 이 팀만 제거했습니다."
  fi
  exit 0
fi
```

- [ ] **Step 5: `--reharness` 의 상태 로드를 팀 단위로**

orch:481-485 를 교체한다.

```bash
if [ -n "$REHARNESS" ]; then
  ORCH_STATE_JSON=$(state_load "$STATE_FILE")
  FT=$(focused_tab)
  WT=""
  if [ -n "$WANT_TAB" ]; then WT=$(resolve_tab "$WANT_TAB"); fi
  set +e
  ORCH_TEAM_JSON=$(state_select_team "$ORCH_STATE_JSON" "$FT" "$WT")
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    echo "이 워크스페이스에 팀이 여러 개입니다. --tab 으로 지정하세요:" >&2
    state_team_menu "$ORCH_STATE_JSON" | column -t -s "$(printf '\t')" >&2
    exit 1
  fi
  if [ "$rc" -eq 0 ]; then
    if [ -z "$TEAM" ]; then TEAM=$(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.team // ""'); fi
    if [ -z "$CWD" ]; then CWD=$(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.cwd // ""'); fi
    ORCH_PANE=$(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.orch_pane // ""')
    echo "상태 로드: $(printf '%s' "$ORCH_TEAM_JSON" | jq -r '.tab_label // .tab') (team=${TEAM:-none})"
  fi
fi
```

`rc` 가 1(팀 없음)이면 기존처럼 `--team` 인자에 의존해 진행한다 — 상태 파일 없이 reharness 하던 경로를 깨지 않는다.

- [ ] **Step 6: 상태 저장을 v2 로**

orch:944-968 의 `printf` JSON 조립을 교체한다. 팀 생성 직후이므로 `TAB1_ID` 를 먼저 구한다.

**위치 주의**: `TAB1_ID` 는 탭 생성 직후(orch:880, `ORCH_PANE` 추출 바로 다음)에 잡는다.
Task 6이 프롬프트에 형제 팀 표를 넣을 때 이 값을 쓰므로, state 저장부에 두면 순서가 어긋난다.

`herdr tab create` 응답이 `.result.tab.tab_id` 를 직접 준다(실측 확인). 팬을 다시 조회할
필요가 없다.

```bash
# 탭 ID 는 tab create 응답에서 바로 꺼낸다
TAB1_ID=$(echo "$TAB1" | jq -r '.result.tab.tab_id // ""')

ROLES_JSON="[]"
i=0
for pid in "${AGENT_PANES[@]}"; do
  nm="${ROLES[i]:-$(role_field $i name)}"
  if [ -z "$nm" ]; then nm="agent-$((i+1))"; fi
  sg=$(role_field "$i" en)
  if [ -z "$sg" ]; then sg="agent-$((i+1))"; fi
  ROLES_JSON=$(printf '%s' "$ROLES_JSON" | jq --argjson idx "$i" \
    --arg n "$nm" --arg s "$sg" --arg p "$pid" \
    '. + [{idx:$idx, name:$n, slug:$s, pane:$p}]')
  i=$((i+1))
done

TEAM_JSON=$(jq -n \
  --arg tab "$TAB1_ID" --arg label "${TAB_LABEL:-orch}" --arg team "${TEAM:-}" \
  --arg cwd "${CWD:-$PWD}" --arg spec "${SPEC:-}" --arg op "$ORCH_PANE" \
  --arg model "$MODEL" --arg lead "$LEAD_MODEL" \
  --arg created "$(date '+%Y-%m-%dT%H:%M:%S')" --argjson roles "$ROLES_JSON" \
  '{tab:$tab, tab_label:$label, team:$team, cwd:$cwd, spec:$spec,
    orch_pane:$op, model:$model, lead_model:$lead, created:$created, roles:$roles}')

CUR=$(state_load "$STATE_FILE")
CUR=$(printf '%s' "$CUR" | jq --arg ws "$WS" '.workspace = $ws')
state_save "$STATE_FILE" "$(state_upsert_team "$CUR" "$TEAM_JSON")"
```

`TAB_LABEL` 은 Task 5에서 `--add-team` 이 설정한다. 지금은 비어 있으므로 `orch` 로 기본값이 들어간다.

- [ ] **Step 7: 문법 검사와 기존 동작 확인**

```bash
bash -n /opt/homebrew/bin/orch && echo "문법 OK"
orch --list-teams
orch --help | head -5
```

Expected: 문법 OK, 팀 목록 정상 출력, 도움말 정상

- [ ] **Step 8: 숨김 워크스페이스에서 생성→정리 왕복**

```bash
WSID=$(herdr workspace create --label orch-test --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id')
echo "테스트 워크스페이스: $WSID"
ORCH_CLAUDE_CMD="echo x" orch 3 --workspace "$WSID" --cwd /tmp
cat ~/.config/herdr/orch/state/$WSID.json | jq '{version, teams:(.teams|length), tab:.teams[0].tab}'
```

Expected: `version: 2`, `teams: 1`, `tab` 이 `<WSID>:t<n>` 형태

```bash
orch --stop --workspace "$WSID" --force
herdr workspace close "$WSID"
```

Expected: 팬이 닫히고 상태에서 팀이 빠진다

- [ ] **Step 9: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add orch tests/
git commit -m "feat: orch 본체를 state v2 로 전환, --tab/--all-teams 추가"
```

`orch` 본체 사본을 저장소에 두어 이후 변경을 추적한다. 실행 파일은 `/opt/homebrew/bin/orch` 그대로다.

---

### Task 4: `--reharness --only <역할>`

**Files:**
- Modify: `/opt/homebrew/bin/orch` (플래그 추가, RH_PLAN 필터 — 기존 780-845 이후)

**Interfaces:**
- Consumes: Task 3의 `ORCH_TEAM_JSON`
- Produces: `--only <역할[,역할]>` 플래그. Task 5의 `orch skill` 이 이것을 호출한다

- [ ] **Step 1: 플래그 추가**

```bash
    --only) IFS=',' read -ra ONLY_ROLES <<< "$2"; shift 2 ;;
```

초기화: `ONLY_ROLES=()`

- [ ] **Step 2: RH_PLAN 필터**

`RH_PLAN` 구성이 끝나고 "계획 출력" 직전(orch:845 부근)에 삽입한다.

```bash
if [ "${#ONLY_ROLES[@]}" -gt 0 ]; then
  FILTERED=()
  for row in "${RH_PLAN[@]}"; do
    IFS=$'\t' read -r _p _n _s _f _m _y _sess <<< "$row"
    for want in "${ONLY_ROLES[@]}"; do
      if [ "$_n" = "$want" ] || [ "$_s" = "$want" ]; then FILTERED+=("$row"); break; fi
    done
  done
  if [ "${#FILTERED[@]}" -eq 0 ]; then
    echo "--only 로 지정한 역할을 찾지 못했습니다: ${ONLY_ROLES[*]}" >&2
    echo "이 팀의 역할:" >&2
    for row in "${RH_PLAN[@]}"; do
      IFS=$'\t' read -r _p _n _s _f _m _y _sess <<< "$row"
      printf '  %s (%s)\n' "$_n" "$_s" >&2
    done
    exit 1
  fi
  RH_PLAN=("${FILTERED[@]}")
  echo "--only: ${#RH_PLAN[@]}개 팬만 재구축합니다"
fi
```

- [ ] **Step 3: dry-run 으로 검증**

```bash
WSID=$(herdr workspace create --label orch-only --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id')
ORCH_CLAUDE_CMD="echo x" orch 3 --workspace "$WSID" --team dev --cwd /tmp
orch --reharness --dry-run --workspace "$WSID" | tail -8
orch --reharness --dry-run --only PM --workspace "$WSID" | tail -5
```

Expected: 첫 번째는 3개 이상, 두 번째는 `--only: 1개 팬만 재구축합니다` 와 PM 한 줄

```bash
orch --reharness --dry-run --only 없는역할 --workspace "$WSID" 2>&1 | head -4
```

Expected: `--only 로 지정한 역할을 찾지 못했습니다` + 역할 목록, exit 1

```bash
orch --stop --workspace "$WSID" --force; herdr workspace close "$WSID"
```

- [ ] **Step 4: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add orch
git commit -m "feat: --reharness --only 로 특정 역할만 재구축"
```

---

### Task 5: `orch skill` 서브커맨드

**Files:**
- Create: `~/.config/herdr/orch/lib/skills.sh`
- Create: `~/.config/herdr/orch/tests/test_skills.sh`
- Modify: `/opt/homebrew/bin/orch` (서브커맨드 라우팅, 인자 파싱 앞)
- Modify: `~/.config/herdr/orch/orchestrator.md` (사용법 주입)

**Interfaces:**
- Consumes: Task 4의 `--only`
- Produces:
  - `skill_is_repo <문자열>` → `owner/repo` 또는 `owner/repo#skill` 이면 0, 아니면 1
  - `skill_target_dir <cwd>` → `<cwd>/.claude/skills`
  - `skill_guard_path <cwd> <설치경로>` → 설치 경로가 cwd 하위가 아니면 1
  - `skill_installed <cwd>` → 설치된 스킬 이름을 한 줄에 하나씩

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > ~/.config/herdr/orch/tests/test_skills.sh <<'EOF'
#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(dirname "$0")/../lib/skills.sh"

skill_is_repo "vercel-labs/skills" && r=0 || r=1
assert_eq "0" "$r" "owner/repo 는 repo 로 본다"
skill_is_repo "vercel-labs/skills#pdf-extract" && r=0 || r=1
assert_eq "0" "$r" "owner/repo#skill 도 repo 로 본다"
skill_is_repo "pdf 추출" && r=0 || r=1
assert_eq "1" "$r" "공백이 있으면 키워드다"
skill_is_repo "typescript" && r=0 || r=1
assert_eq "1" "$r" "슬래시가 없으면 키워드다"
skill_is_repo "a/b/c" && r=0 || r=1
assert_eq "1" "$r" "슬래시가 둘이면 repo 가 아니다"

assert_eq "/tmp/proj/.claude/skills" "$(skill_target_dir /tmp/proj)" "설치 경로는 cwd 하위 .claude/skills"

skill_guard_path "/tmp/proj" "/tmp/proj/.claude/skills/x" && r=0 || r=1
assert_eq "0" "$r" "cwd 하위 경로는 통과한다"
skill_guard_path "/tmp/proj" "/Users/me/.claude/skills/x" && r=0 || r=1
assert_eq "1" "$r" "전역 경로는 막는다"
skill_guard_path "/tmp/proj" "/tmp/proj/../other/x" && r=0 || r=1
assert_eq "1" "$r" "상위로 빠져나가는 경로는 막는다"

TMP=$(mktemp -d)
mkdir -p "$TMP/.claude/skills/alpha" "$TMP/.claude/skills/beta"
assert_eq "alpha
beta" "$(skill_installed "$TMP")" "설치된 스킬을 나열한다"
assert_eq "" "$(skill_installed /tmp/nonexistent-$$)" "없는 디렉토리는 빈 목록이다"
rm -rf "$TMP"

summary
EOF
```

- [ ] **Step 2: 실패 확인**

Run: `bash ~/.config/herdr/orch/tests/test_skills.sh`
Expected: FAIL — `lib/skills.sh: No such file or directory`

- [ ] **Step 3: 구현**

```bash
cat > ~/.config/herdr/orch/lib/skills.sh <<'EOF'
#!/bin/bash
# npx skills 래퍼. 설치는 항상 에이전트 cwd 하위로 격리한다.
# 전역(-g) 설치는 하지 않는다 — 수십 개 세션이 도는 환경에서 서로를 오염시킨다.

SKILLS_NPX="${ORCH_NPX_CMD:-npx}"   # 테스트에서 스텁으로 치환

# owner/repo 또는 owner/repo#skill 이면 0(=repo), 그 외는 1(=키워드)
skill_is_repo() { # <문자열>
  case "$1" in
    *" "*) return 1 ;;
    */*/*) return 1 ;;
    */*)   return 0 ;;
    *)     return 1 ;;
  esac
}

skill_target_dir() { # <cwd>
  printf '%s/.claude/skills' "$1"
}

# 설치 경로가 cwd 하위인지 확인한다. 심볼릭 링크·상위 참조를 모두 정규화해서 본다.
skill_guard_path() { # <cwd> <설치경로>
  local base real
  base=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  # 아직 없는 경로일 수 있으므로 존재하는 상위까지만 정규화한 뒤 나머지를 붙인다
  real=$(cd "$(dirname "$2")" 2>/dev/null && pwd -P)/$(basename "$2") 2>/dev/null
  if [ -z "$real" ]; then
    case "$2" in "$base"/*) return 0 ;; *) return 1 ;; esac
  fi
  case "$real" in "$base"/*) return 0 ;; *) return 1 ;; esac
}

skill_installed() { # <cwd>
  local d
  d=$(skill_target_dir "$1")
  [ -d "$d" ] || return 0
  ls -1 "$d" 2>/dev/null
}

# 후보 검색. 출력은 한 줄에 하나. 실패해도 스크립트를 죽이지 않는다.
skill_find() { # <키워드>
  "$SKILLS_NPX" skills find "$1" 2>/dev/null || true
}

# 설치. 경로 가드를 통과해야만 실행한다.
skill_add() { # <cwd> <repo>
  local dir
  dir=$(skill_target_dir "$1")
  if ! skill_guard_path "$1" "$dir"; then
    printf '설치 경로가 작업 디렉토리를 벗어납니다: %s\n' "$dir" >&2
    return 1
  fi
  mkdir -p "$dir"
  ( cd "$1" && "$SKILLS_NPX" skills add "$2" )
}
EOF
```

`skill_guard_path` 의 `pwd -P` 는 심볼릭 링크를 풀어 `..` 우회를 막는다.

- [ ] **Step 4: 통과 확인**

Run: `bash ~/.config/herdr/orch/tests/run.sh`
Expected: 전부 통과

- [ ] **Step 5: orch 에 서브커맨드 라우팅**

인자 파싱 while 루프 **앞**에 둔다. `orch skill ...` 은 팬을 만들지 않으므로 일찍 갈라져야 한다.

```bash
if [ "${1:-}" = "skill" ]; then
  shift
  . "$PROMPT_DIR/lib/skills.sh"
  SK_ACTION="${1:-}"; shift || true
  SK_ROLE=""; SK_TARGET=""; SK_WS=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) SK_ROLE="$2"; shift 2 ;;
      --workspace) SK_WS="$2"; shift 2 ;;
      *) SK_TARGET="$1"; shift ;;
    esac
  done
  if [ -z "$SK_WS" ]; then
    SK_WS=$(herdr workspace list 2>/dev/null | jq -r '.result.workspaces[]? | select(.focused==true) | .workspace_id' | head -1)
  fi
  SK_STATE=$(state_load "$PROMPT_DIR/state/$SK_WS.json")
  SK_CWD=$(printf '%s' "$SK_STATE" | jq -r '.teams[0].cwd // ""')
  if [ -z "$SK_CWD" ]; then SK_CWD="$PWD"; fi

  case "$SK_ACTION" in
    list)
      printf '설치된 스킬 (%s):\n' "$(skill_target_dir "$SK_CWD")"
      found=$(skill_installed "$SK_CWD")
      if [ -z "$found" ]; then echo "  (없음)"; else printf '%s\n' "$found" | sed 's/^/  /'; fi
      exit 0 ;;
    find)
      if [ -z "$SK_TARGET" ]; then echo "검색어가 필요합니다: orch skill find <키워드>" >&2; exit 1; fi
      echo "'$SK_TARGET' 검색 결과:"
      res=$(skill_find "$SK_TARGET")
      if [ -z "$res" ]; then echo "  후보가 없습니다."; else printf '%s\n' "$res" | sed 's/^/  /'; fi
      exit 0 ;;
    add)
      if [ -z "$SK_TARGET" ]; then echo "대상이 필요합니다: orch skill add <repo|키워드> --role <역할>" >&2; exit 1; fi
      if skill_is_repo "$SK_TARGET"; then
        REPO="$SK_TARGET"
      else
        echo "'$SK_TARGET' 로 검색합니다..."
        CAND=$(skill_find "$SK_TARGET")
        if [ -z "$CAND" ]; then echo "후보가 없습니다. 다른 키워드로 찾아보세요." >&2; exit 1; fi
        CNT=$(printf '%s\n' "$CAND" | grep -c . || true)
        if [ "$CNT" -gt 1 ]; then
          echo "후보가 여러 개입니다. owner/repo 형태로 다시 지정하세요:" >&2
          printf '%s\n' "$CAND" | sed 's/^/  /' >&2
          exit 2
        fi
        REPO=$(printf '%s\n' "$CAND" | head -1)
        echo "선택: $REPO"
      fi
      echo "설치 위치: $(skill_target_dir "$SK_CWD")"
      skill_add "$SK_CWD" "$REPO" || { echo "설치 실패: $REPO" >&2; exit 1; }
      echo "설치 완료: $REPO"
      if [ -n "$SK_ROLE" ]; then
        echo "역할 '$SK_ROLE' 재구축 중..."
        orch --reharness --only "$SK_ROLE" --workspace "$SK_WS"
      else
        echo "적용하려면: orch --reharness --workspace $SK_WS"
      fi
      exit 0 ;;
    remove)
      if [ -z "$SK_TARGET" ]; then echo "제거할 스킬 이름이 필요합니다" >&2; exit 1; fi
      DIR="$(skill_target_dir "$SK_CWD")/$SK_TARGET"
      if ! skill_guard_path "$SK_CWD" "$DIR"; then echo "경로 위반: $DIR" >&2; exit 1; fi
      if [ ! -e "$DIR" ]; then echo "그런 스킬이 없습니다: $SK_TARGET" >&2; exit 1; fi
      rm -rf "$DIR"
      echo "제거 완료: $SK_TARGET"
      if [ -n "$SK_ROLE" ]; then orch --reharness --only "$SK_ROLE" --workspace "$SK_WS"; fi
      exit 0 ;;
    *)
      echo "사용법: orch skill <find|add|list|remove> [대상] [--role 역할]" >&2
      exit 1 ;;
  esac
fi
```

- [ ] **Step 6: npx 스텁으로 검증**

실제 네트워크를 타지 않고 확인한다.

```bash
STUB=$(mktemp -d)
cat > "$STUB/npx" <<'EOF'
#!/bin/bash
# skills find <kw> → 후보 1개, skills add <repo> → 디렉토리 생성
if [ "$2" = "find" ]; then echo "vercel-labs/skills#stub-$3"; exit 0; fi
if [ "$2" = "add" ]; then mkdir -p ".claude/skills/$(basename "$3" | tr -d '#')"; echo "installed $3"; exit 0; fi
EOF
chmod +x "$STUB/npx"
WORK=$(mktemp -d)
ORCH_NPX_CMD="$STUB/npx" bash -c ". ~/.config/herdr/orch/lib/skills.sh; skill_add '$WORK' 'vercel-labs/skills#pdf'"
ls "$WORK/.claude/skills/"
```

Expected: `skillspdf` 같은 디렉토리 하나. `~/.claude/skills/` 는 변하지 않음

```bash
ls ~/.claude/skills/
```

Expected: `synced` 만 — 전역이 오염되지 않았음을 확인

```bash
rm -rf "$STUB" "$WORK"
```

- [ ] **Step 7: 오케스트레이터 프롬프트에 사용법 주입**

`orchestrator.md` 끝에 덧붙인다.

```bash
cat >> ~/.config/herdr/orch/orchestrator.md <<'EOF'

## 에이전트 업그레이드 (스킬 주입)

에이전트가 지금 능력이 모자라 막혀 있다면, 스킬을 찾아 넣어줄 수 있다.

```
orch skill find <키워드>              후보를 본다
orch skill add <owner/repo> --role <역할>   설치하고 그 역할만 재기동
orch skill list                       지금 뭐가 깔려 있나
```

- 설치는 팀 작업 디렉토리의 `.claude/skills/` 로 격리된다. 다른 팀에는 영향이 없다
- `--role` 을 주면 그 팬만 `--resume` 으로 재기동하므로 **대화 맥락이 유지된다**
- 후보가 여러 개면 명령이 목록을 주고 멈춘다. 네가 골라 `owner/repo` 로 다시 실행해라
- 사용자 승인은 필요 없다. 다만 무엇을 왜 넣는지는 comms 로그에 남겨라
EOF
```

- [ ] **Step 8: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add lib/skills.sh tests/test_skills.sh orch orchestrator.md
git commit -m "feat: orch skill 서브커맨드로 운영 중 에이전트 업그레이드"
```

---

### Task 6: `--add-team` 팀 증설

**Files:**
- Modify: `/opt/homebrew/bin/orch` (플래그, 탭 생성 분기, 형제 팀 주입)

**Interfaces:**
- Consumes: Task 1의 `state_upsert_team`, Task 3의 `TAB_LABEL`/`TAB1_ID`
- Produces: `--add-team <용도|팀>`, `--name <탭label>` 플래그

- [ ] **Step 1: 플래그 추가**

```bash
    --add-team) ADD_TEAM="$2"; shift 2 ;;
    --name) TAB_NAME="$2"; shift 2 ;;
```

초기화: `ADD_TEAM=""`, `TAB_NAME=""`, `TAB_LABEL="orch"`

- [ ] **Step 2: 증설 모드 진입 처리**

팀 프리셋 로드(orch:488 부근) **직전**에 둔다. `--add-team` 은 `--team` 과 같은 경로를 타되 탭 라벨만 달라진다.

```bash
if [ -n "$ADD_TEAM" ]; then
  # 용도 별칭을 프리셋 이름으로 바꾼다
  case "$ADD_TEAM" in
    개발|dev)      TEAM="dev" ;;
    분석|analysis) TEAM="analysis" ;;
    기획|planning) TEAM="planning" ;;
    테스트|qa)     TEAM="qa" ;;
    *)             TEAM="$ADD_TEAM" ;;
  esac
  if [ -n "$TAB_NAME" ]; then TAB_LABEL="$TAB_NAME"; else TAB_LABEL="orch-$TEAM"; fi

  # 같은 라벨의 탭이 이미 있으면 뒤에 번호를 붙인다
  EXIST=$(herdr tab list --workspace "$WS" 2>/dev/null \
    | jq -r --arg l "$TAB_LABEL" '[.result.tabs[]? | select((.label // "") | startswith($l))] | length')
  if [ "$EXIST" -gt 0 ]; then TAB_LABEL="$TAB_LABEL-$((EXIST+1))"; fi
  echo "팀 증설: 새 탭 '$TAB_LABEL' 에 $TEAM 팀을 만듭니다"
fi
```

- [ ] **Step 3: 중복 팀 방지 우회**

orch:870 부근의 중복 팀 검사는 워크스페이스에 팀이 있으면 막는다. 증설은 그게 정상이므로 통과시킨다. 검사 조건에 `[ -z "$ADD_TEAM" ]` 를 추가한다.

```bash
if [ -z "$FORCE" ] && [ -z "$ADD_TEAM" ]; then
```

- [ ] **Step 4: 탭 라벨 반영**

orch:880 의 탭 생성에서 `--label orch` 를 변수로 바꾼다.

```bash
TAB1=$(herdr tab create --workspace "$WS" --label "$TAB_LABEL" "${TAB_CWD[@]+"${TAB_CWD[@]}"}" --focus)
```

- [ ] **Step 5: 형제 팀 표를 오케 프롬프트에 주입**

오케스트레이터 프롬프트 생성부(orch:905 이후)에 덧붙인다.

```bash
SIBLINGS=$(state_load "$STATE_FILE" | jq -r --arg tab "$TAB1_ID" '
  (.teams // [])[] | select(.tab != $tab)
  | "| \(.team // "커스텀") | \(.tab_label // .tab) | \(.orch_pane) |"')
if [ -n "$SIBLINGS" ]; then
  {
    printf '\n## 같은 워크스페이스의 다른 팀\n\n'
    printf '| 팀 | 탭 | 오케 팬 |\n|---|---|---|\n'
    printf '%s\n' "$SIBLINGS"
    printf '\n규칙: 다른 팀에는 **그 팀의 오케 팬에만** 보낸다.\n'
    printf '남의 팀 에이전트에 직접 보내지 마라 — 그 팀 오케가 상황을 모르게 된다.\n'
  } >> "$RUN_DIR/orch.md"
fi
```

`TAB1_ID` 는 Task 3에서 이미 구해 둔다. 순서상 state 저장보다 앞이므로, `TAB1_ID` 계산을 프롬프트 생성 앞으로 옮긴다.

- [ ] **Step 6: 기존 팀 오케에게 알린다**

state 저장 직후에 둔다. 재기동이 아니라 메시지 1회다 — 진행 중 작업을 끊지 않는다.

```bash
if [ -n "$ADD_TEAM" ]; then
  OLD_ORCHS=$(state_load "$STATE_FILE" | jq -r --arg tab "$TAB1_ID" \
    '(.teams // [])[] | select(.tab != $tab) | .orch_pane')
  for op in $OLD_ORCHS; do
    case "$op" in "$WS":*) ;; *) continue ;; esac
    herdr agent send "$op" "[orch] 같은 워크스페이스에 새 팀이 생겼다: $TEAM (탭 $TAB_LABEL, 오케 팬 $ORCH_PANE). 협업이 필요하면 그 팬으로 보내라." >/dev/null 2>&1 || true
    herdr pane send-keys "$op" enter >/dev/null 2>&1 || true
  done
fi
```

`herdr agent send` 는 입력만 하고 제출하지 않으므로 `send-keys enter` 가 반드시 뒤따라야 한다.

- [ ] **Step 7: 검증**

```bash
WSID=$(herdr workspace create --label orch-add --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id')
ORCH_CLAUDE_CMD="echo x" orch 2 --workspace "$WSID" --team dev --cwd /tmp
ORCH_CLAUDE_CMD="echo x" orch 2 --workspace "$WSID" --add-team qa --cwd /tmp
jq '{teams:(.teams|length), labels:[.teams[].tab_label], tabs:[.teams[].tab]}' ~/.config/herdr/orch/state/$WSID.json
```

Expected: `teams: 2`, labels `["orch","orch-qa"]`, 탭 ID 두 개가 서로 다름

```bash
herdr tab list --workspace "$WSID" | jq -r '.result.tabs[] | "\(.tab_id) \(.label)"'
```

Expected: `orch` 탭과 `orch-qa` 탭이 각각 존재

```bash
orch --stop --tab orch-qa --workspace "$WSID" --force
jq '{teams:(.teams|length), labels:[.teams[].tab_label]}' ~/.config/herdr/orch/state/$WSID.json
```

Expected: `teams: 1`, `["orch"]` — 기존 팀은 그대로

```bash
orch --stop --all-teams --workspace "$WSID" --force; herdr workspace close "$WSID"
```

- [ ] **Step 8: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add orch
git commit -m "feat: --add-team 으로 같은 워크스페이스에 팀 증설"
```

---

### Task 7: 팀 프리셋 3종

**Files:**
- Create: `~/.config/herdr/orch/teams/analysis.json`
- Create: `~/.config/herdr/orch/teams/planning.json`
- Create: `~/.config/herdr/orch/teams/qa.json`

**Interfaces:**
- Consumes: 기존 `validate_spec()` (orch:139) — `name`, `roles[].name`, `roles[].prompt` 필수
- Produces: Task 8의 마법사가 용도→팀으로 매핑할 대상

기존 `dev.json` 과 동일한 형식을 따른다: `name`, `model`, `description`, `flow`, `guides`, `roles[]{name,en,brief,prompt,mcp,plugins,ref_agents}`.

- [ ] **Step 1: analysis.json**

```bash
cat > ~/.config/herdr/orch/teams/analysis.json <<'EOF'
{
  "name": "분석팀",
  "model": "Data Mesh / 분석 스쿼드",
  "description": "질문을 데이터로 답하는 팀. 가설 → 수집 → 검증 → 해석 → 의사결정 자료까지 한 사이클을 돈다.",
  "flow": "분석리드(질문 정의) → 데이터엔지니어(수집·정제) → 분석가(탐색·통계) → 검증(재현·반례) → 시각화(전달) → 분석리드(의사결정 권고)",
  "guides": ["handoff.md"],
  "roles": [
    {"name": "분석리드", "en": "analytics-lead",
     "brief": "질문을 정의하고 분석 범위와 성공 기준을 정한다",
     "prompt": "너는 분석의 단일 책임자다. 가장 먼저 '무엇을 알면 무엇을 결정할 수 있는가'를 한 문장으로 적고 시작한다. 답이 의사결정을 바꾸지 못하는 질문은 잘라낸다. 분석 결과를 받으면 반드시 '그래서 무엇을 하자'는 권고까지 만든다. 데이터가 부족해 답할 수 없으면 그 사실을 결론으로 낸다.",
     "mcp": ["notion"], "plugins": [], "ref_agents": []},
    {"name": "데이터엔지니어", "en": "data-engineer",
     "brief": "원천 데이터 수집·정제·적재, 재현 가능한 파이프라인 구축",
     "prompt": "너는 데이터를 신뢰할 수 있게 만드는 사람이다. 수집한 데이터는 반드시 출처·수집시각·행수를 기록한다. 정제 단계는 스크립트로 남겨 누구나 재현할 수 있게 한다. 손으로 고친 데이터는 절대 넘기지 않는다. 결측·이상치는 지우지 말고 표시해서 분석가에게 넘긴다.",
     "mcp": ["serena"], "plugins": [], "ref_agents": []},
    {"name": "분석가", "en": "data-analyst",
     "brief": "탐색적 분석, 통계 검정, 패턴 발견",
     "prompt": "너는 데이터에서 패턴을 찾는다. 결론을 내기 전에 반드시 '이 패턴이 우연일 확률'을 따진다. 표본 수가 작으면 작다고 명시한다. 상관을 인과로 말하지 않는다. 시각화는 검증 담당에게 넘기기 전 스스로 반례를 한 번 찾아본다.",
     "mcp": [], "plugins": [], "ref_agents": []},
    {"name": "검증", "en": "analysis-verifier",
     "brief": "분석 결과 재현, 반례 탐색, 방법론 감사",
     "prompt": "너는 분석 결과를 의심하는 역할이다. 같은 데이터로 같은 결론이 나오는지 독립적으로 재현한다. 표본 편향·생존자 편향·기간 선택 편향을 먼저 의심한다. 반례를 하나라도 찾으면 그 사실을 결론보다 앞에 적는다. 통과시킬 때도 '어떤 조건에서만 성립하는가'를 남긴다.",
     "mcp": [], "plugins": [], "ref_agents": []},
    {"name": "시각화", "en": "data-viz",
     "brief": "결과를 의사결정자가 5초 안에 이해할 형태로 만든다",
     "prompt": "너는 분석 결과를 전달 가능한 형태로 만든다. 차트 하나에 메시지 하나만 담는다. 축을 자르거나 비율을 왜곡해 인상을 조작하지 않는다. 제목에 결론을 쓴다 — '월별 매출'이 아니라 '3월 이후 매출이 꺾였다'. 불확실성이 큰 수치는 범위로 보여준다.",
     "mcp": ["figma"], "plugins": [], "ref_agents": []},
    {"name": "사서", "en": "librarian",
     "brief": "분석 산출물·데이터 사전·과거 분석 이력을 관리한다",
     "prompt": "너는 팀의 기억이다. 모든 분석은 질문·데이터출처·방법·결론·한계를 한 문서로 남긴다. 같은 질문이 다시 오면 과거 분석을 먼저 찾아 제시한다. 데이터 정의가 바뀌면 과거 분석 중 영향받는 것을 찾아 표시한다.",
     "mcp": ["notion"], "plugins": [], "ref_agents": []}
  ]
}
EOF
jq -e . ~/.config/herdr/orch/teams/analysis.json >/dev/null && echo "analysis.json JSON OK"
```

- [ ] **Step 2: planning.json**

```bash
cat > ~/.config/herdr/orch/teams/planning.json <<'EOF'
{
  "name": "기획팀",
  "model": "Discovery Squad / 듀얼 트랙 애자일",
  "description": "무엇을 왜 만들지 정하는 팀. 문제 정의 → 사용자 검증 → 명세 → 우선순위까지 끌고 간다. 구현은 하지 않는다.",
  "flow": "기획리드(문제 정의) → 리서치(사용자·시장) → 명세(요구사항·플로우) → 비판(반대 논거) → 기획리드(우선순위 확정 → 개발팀 인계)",
  "guides": ["handoff.md"],
  "roles": [
    {"name": "기획리드", "en": "product-lead",
     "brief": "문제를 정의하고 무엇을 만들지 결정한다",
     "prompt": "너는 '무엇을 왜'의 책임자다. 해결책부터 말하지 않는다 — 누가 어떤 상황에서 무엇 때문에 곤란한지를 먼저 적는다. 기능 아이디어가 오면 '이게 없으면 사용자가 무엇을 못 하는가'로 되묻는다. 우선순위는 반드시 근거와 함께 정한다. 구현 방법은 개발팀에 위임한다.",
     "mcp": ["linear", "notion"], "plugins": [], "ref_agents": []},
    {"name": "리서치", "en": "user-researcher",
     "brief": "사용자 인터뷰·경쟁 제품·시장 자료로 가정을 검증한다",
     "prompt": "너는 팀의 가정을 사실로 바꾸거나 깨는 역할이다. '사용자가 원할 것이다'는 문장을 보면 근거를 찾으러 간다. 근거를 찾을 때는 출처와 날짜를 반드시 남긴다. 우리 제품에 유리한 자료만 모으지 않는다 — 반대 증거를 최소 하나는 함께 가져온다.",
     "mcp": ["notion"], "plugins": [], "ref_agents": []},
    {"name": "명세", "en": "spec-writer",
     "brief": "요구사항·사용자 플로우·완료 조건을 문서로 확정한다",
     "prompt": "너는 애매함을 없애는 사람이다. 모든 요구사항에 완료 조건(Acceptance Criteria)을 붙인다. '적절히', '사용자 친화적으로' 같은 말은 쓰지 않는다 — 측정 가능한 문장으로 바꾼다. 예외 흐름(실패·빈 상태·권한 없음)을 정상 흐름과 같은 비중으로 적는다.",
     "mcp": ["notion", "linear"], "plugins": [], "ref_agents": []},
    {"name": "비판", "en": "devils-advocate",
     "brief": "기획의 반대 논거를 만들어 약점을 미리 드러낸다",
     "prompt": "너는 이 기획에 반대하는 역할을 맡는다. 만들지 말아야 할 이유를 최소 세 개 만든다. 가장 낙관적인 가정이 무엇인지 찾아내 그것이 틀렸을 때 무슨 일이 생기는지 적는다. 비판만 하고 끝내지 말고 '그럼에도 한다면 이 조건은 확인해야 한다'를 남긴다.",
     "mcp": [], "plugins": [], "ref_agents": []},
    {"name": "디자이너", "en": "product-designer",
     "brief": "화면 플로우와 와이어프레임으로 기획을 눈에 보이게 만든다",
     "prompt": "너는 기획을 그림으로 검증한다. 화면을 그리기 전에 진입→목표달성→이탈 경로를 먼저 정리한다. 빈 상태·로딩·에러 화면을 반드시 함께 그린다. 기존 디자인 시스템이 있으면 Figma MCP로 먼저 확인하고 거기 맞춘다.",
     "mcp": ["figma"], "plugins": ["frontend-design@claude-plugins-official"], "ref_agents": []},
    {"name": "사서", "en": "librarian",
     "brief": "기획 문서·결정 이력·폐기된 안을 관리한다",
     "prompt": "너는 팀의 기억이다. 모든 결정은 '무엇을 왜 골랐고 무엇을 왜 버렸는지'로 남긴다. 같은 논의가 반복되면 과거 결정을 찾아 제시한다. 폐기한 안도 지우지 않는다 — 나중에 조건이 바뀌면 다시 꺼내야 한다.",
     "mcp": ["notion"], "plugins": [], "ref_agents": []}
  ]
}
EOF
jq -e . ~/.config/herdr/orch/teams/planning.json >/dev/null && echo "planning.json JSON OK"
```

- [ ] **Step 3: qa.json**

```bash
cat > ~/.config/herdr/orch/teams/qa.json <<'EOF'
{
  "name": "테스트팀",
  "model": "Quality Engineering / Shift-Left",
  "description": "품질을 마지막 관문이 아니라 전 과정에 넣는 팀. 테스트 설계 → 자동화 → 탐색적 테스트 → 회귀 방지까지 담당한다.",
  "flow": "QA리드(전략·범위) → 테스트설계(케이스) → 자동화(스크립트) → 탐색(수동·엣지) → 성능/보안(비기능) → QA리드(릴리스 판정)",
  "guides": ["handoff.md"],
  "roles": [
    {"name": "QA리드", "en": "qa-lead",
     "brief": "테스트 전략·범위·릴리스 판정 기준을 정한다",
     "prompt": "너는 '이걸 내보내도 되는가'의 책임자다. 테스트 전에 무엇을 확인하면 통과인지 기준을 먼저 적는다. 시간이 모자라면 전부 조금씩 하지 말고 위험이 큰 곳에 몰아준다. 버그를 못 찾은 것과 버그가 없는 것을 구별해서 보고한다.",
     "mcp": ["linear"], "plugins": [], "ref_agents": []},
    {"name": "테스트설계", "en": "test-designer",
     "brief": "요구사항에서 테스트 케이스를 도출한다",
     "prompt": "너는 명세를 테스트 케이스로 바꾼다. 정상 경로보다 경계값과 예외에 더 많은 케이스를 쓴다. 빈 값·최대 길이·중복·동시 요청·권한 없음을 기본 목록으로 둔다. 케이스마다 '무엇을 확인하는가'를 한 줄로 적어 나중에 왜 이 테스트가 있는지 알 수 있게 한다.",
     "mcp": [], "plugins": [], "ref_agents": []},
    {"name": "자동화", "en": "test-automation",
     "brief": "반복 실행할 테스트를 코드로 만든다",
     "prompt": "너는 사람이 두 번 할 일을 기계에 넘긴다. 테스트는 독립적으로 돌아가야 한다 — 실행 순서에 의존하는 테스트는 만들지 않는다. 불안정하게 가끔 실패하는 테스트는 고치거나 지운다. 방치하면 팀이 실패를 무시하게 되고 그때부터 테스트는 없는 것과 같다.",
     "mcp": ["playwright", "github"], "plugins": [], "ref_agents": []},
    {"name": "탐색", "en": "exploratory-tester",
     "brief": "정해진 케이스 밖에서 문제를 찾는다",
     "prompt": "너는 명세에 없는 방식으로 제품을 쓴다. 뒤로가기·새로고침·중복 클릭·느린 네트워크·중간 이탈을 시도한다. 개발자가 예상하지 않았을 순서로 조작한다. 찾은 문제는 반드시 재현 절차를 적는다 — 재현 안 되는 버그 리포트는 없는 것과 같다.",
     "mcp": ["playwright"], "plugins": [], "ref_agents": []},
    {"name": "성능보안", "en": "nonfunctional-tester",
     "brief": "부하·응답시간·권한·입력 검증 등 비기능 요구를 확인한다",
     "prompt": "너는 기능이 아니라 조건을 시험한다. 부하는 평소의 몇 배까지 견디는지 숫자로 답한다. 권한 검사는 '되는 것'이 아니라 '안 되어야 하는 것'을 확인한다. 입력 검증은 서버에서 하는지 본다 — 화면에서만 막는 것은 막은 게 아니다.",
     "mcp": [], "plugins": ["security-review@claude-plugins-official"], "ref_agents": []},
    {"name": "사서", "en": "librarian",
     "brief": "버그 이력·회귀 목록·테스트 자산을 관리한다",
     "prompt": "너는 팀의 기억이다. 한 번 난 버그는 회귀 목록에 넣어 다시 나는지 매번 확인한다. 같은 원인의 버그가 반복되면 그 사실을 묶어서 보고한다 — 개별 버그가 아니라 구조 문제일 수 있다.",
     "mcp": ["notion"], "plugins": [], "ref_agents": []}
  ]
}
EOF
jq -e . ~/.config/herdr/orch/teams/qa.json >/dev/null && echo "qa.json JSON OK"
```

- [ ] **Step 4: validate_spec 통과 확인**

```bash
for t in analysis planning qa; do
  printf '%-10s ' "$t"
  orch --show "$t" >/dev/null 2>&1 && echo "검증 통과" || echo "검증 실패"
done
orch --list-teams
```

Expected: 세 팀 모두 검증 통과, `--list-teams` 에 10개 팀이 나온다

- [ ] **Step 5: 커밋**

```bash
cd ~/.config/herdr/orch
git add teams/
git commit -m "feat: analysis/planning/qa 팀 프리셋 추가"
```

---

### Task 7.5: `orch --self` — orch 자체 관리 세션

**Files:**
- Create: `~/.config/herdr/orch/admin.md`
- Modify: `/opt/homebrew/bin/orch` (`--self` 플래그와 전용 생성 경로)

**Interfaces:**
- Consumes: Task 1의 `state_load`
- Produces: `--self` 플래그. Task 8의 마법사 6번이 이것을 호출한다

orch 를 고도화·관리하는 전용 claude 세션. 팀이 아니라 팬 하나이고, 작업 디렉토리는
`~/.config/herdr/orch` 다. 이미 있으면 새로 만들지 않고 그 팬으로 포커스만 옮긴다.

- [ ] **Step 1: 관리자 프롬프트 작성**

무엇을 만지는 사람인지, 어디를 보면 되는지, 무엇을 하면 안 되는지를 담는다.

```bash
cat > ~/.config/herdr/orch/admin.md <<'EOF'
너는 orch 명령어 자체를 고도화하고 관리하는 담당자다.
(내용은 구현 시 작성)
EOF
```

- [ ] **Step 2: `--self` 플래그와 생성 경로 구현**

- `setting` 라벨의 워크스페이스를 찾고 없으면 만든다
- 그 안에 `orch-admin` 탭을 만들어 팬 하나에 claude 를 띄운다
- 이미 관리 팬이 있으면 만들지 않고 포커스만 옮긴다
- cwd 는 `~/.config/herdr/orch` 로 고정한다

- [ ] **Step 3: 검증**

두 번 실행해서 두 번째가 새로 만들지 않고 기존 팬을 찾는지 확인한다.

- [ ] **Step 4: 커밋**

---

### Task 8: 대화형 마법사

**Files:**
- Create: `~/.config/herdr/orch/lib/wizard.sh`
- Create: `~/.config/herdr/orch/tests/test_wizard.sh`
- Modify: `/opt/homebrew/bin/orch` (인자 0개일 때 진입)

**Interfaces:**
- Consumes: Task 7의 프리셋 3종
- Produces: `wizard_purpose_to_team <번호|이름>` → 프리셋 이름. `wizard_build_cmd <team> <wiki> <n> <model> <lead>` → 실행할 명령줄 문자열

- [ ] **Step 1: 실패하는 테스트 작성**

```bash
cat > ~/.config/herdr/orch/tests/test_wizard.sh <<'EOF'
#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(dirname "$0")/../lib/wizard.sh"

assert_eq "dev" "$(wizard_purpose_to_team 1)" "1번은 개발팀"
assert_eq "analysis" "$(wizard_purpose_to_team 2)" "2번은 분석팀"
assert_eq "planning" "$(wizard_purpose_to_team 3)" "3번은 기획팀"
assert_eq "qa" "$(wizard_purpose_to_team 4)" "4번은 테스트팀"
assert_eq "" "$(wizard_purpose_to_team 5)" "5번(기타)은 팀이 없다"
assert_eq "dev" "$(wizard_purpose_to_team 개발)" "한글 이름도 받는다"

C=$(wizard_build_cmd "dev" "" "4" "opus" "claude-opus-5[1m]")
assert_contains "$C" "orch 4" "에이전트 수가 들어간다"
assert_contains "$C" "--team dev" "팀이 들어간다"
assert_eq "0" "$(printf '%s' "$C" | grep -c -- '--wiki' || true)" "위키가 비면 플래그를 안 넣는다"

C=$(wizard_build_cmd "dev" "/tmp/w" "4" "opus" "claude-opus-5[1m]")
assert_contains "$C" "--wiki /tmp/w" "위키 경로가 들어간다"

C=$(wizard_build_cmd "" "" "3" "sonnet" "claude-opus-5[1m]")
assert_eq "0" "$(printf '%s' "$C" | grep -c -- '--team' || true)" "팀이 비면 플래그를 안 넣는다"
assert_contains "$C" "--model sonnet" "기본값과 다른 모델은 플래그로 넣는다"

C=$(wizard_build_cmd "dev" "" "4" "opus" "claude-opus-5[1m]")
assert_eq "0" "$(printf '%s' "$C" | grep -c -- '--model' || true)" "기본 모델이면 플래그를 생략한다"

summary
EOF
```

- [ ] **Step 2: 실패 확인**

Run: `bash ~/.config/herdr/orch/tests/test_wizard.sh`
Expected: FAIL — `lib/wizard.sh: No such file or directory`

- [ ] **Step 3: 구현**

```bash
cat > ~/.config/herdr/orch/lib/wizard.sh <<'EOF'
#!/bin/bash
# 대화형 마법사. 답변을 기존 플래그로 번역하는 것이 전부다 —
# 새 실행 경로를 만들지 않으므로 플래그 사용자와 동작이 갈라지지 않는다.

WIZ_DEFAULT_MODEL="${ORCH_MODEL:-opus}"
WIZ_DEFAULT_LEAD="${ORCH_LEAD_MODEL:-claude-opus-5[1m]}"

wizard_purpose_to_team() { # <번호|이름>
  case "$1" in
    1|개발|dev)      printf 'dev' ;;
    2|분석|analysis) printf 'analysis' ;;
    3|기획|planning) printf 'planning' ;;
    4|테스트|qa)     printf 'qa' ;;
    *)               printf '' ;;
  esac
}

# 실행할 명령줄을 문자열로 만든다. 기본값과 같은 항목은 플래그를 생략해
# 사용자가 화면에서 보는 명령이 짧고 읽기 쉽게 한다.
wizard_build_cmd() { # <team> <wiki> <n> <model> <lead>
  local team="$1" wiki="$2" n="$3" model="$4" lead="$5" cmd
  cmd="orch $n"
  if [ -n "$team" ]; then cmd="$cmd --team $team"; fi
  if [ -n "$wiki" ]; then cmd="$cmd --wiki $wiki"; fi
  if [ "$model" != "$WIZ_DEFAULT_MODEL" ]; then cmd="$cmd --model $model"; fi
  if [ "$lead" != "$WIZ_DEFAULT_LEAD" ]; then cmd="$cmd --orch-model $lead"; fi
  printf '%s' "$cmd"
}

# 대화형 질문. tty 가 없으면 호출하면 안 된다 (호출부가 판단한다).
wizard_run() { # 결과를 WIZ_CMD 에 담는다
  local purpose team wiki n model lead roles ans
  printf '\n사용할 팀을 고르세요.\n'
  printf '  1) 개발   — 기획·설계·구현·QA·배포를 한 팀에서\n'
  printf '  2) 분석   — 데이터 수집·검증·해석·시각화\n'
  printf '  3) 기획   — 문제 정의·사용자 검증·명세·우선순위\n'
  printf '  4) 테스트 — 테스트 설계·자동화·탐색·성능보안\n'
  printf '  5) 기타   — 역할을 직접 정한다\n'
  printf '  6) orch 관리 — orch 명령어 자체를 고도화·관리하는 세션\n'
  printf '선택 [1]: '
  read -r purpose </dev/tty || purpose=""
  if [ -z "$purpose" ]; then purpose=1; fi
  team=$(wizard_purpose_to_team "$purpose")

  roles=""
  if [ -z "$team" ]; then
    printf '역할 이름을 쉼표로 적으세요 (예: 리서치,구현,검증): '
    read -r roles </dev/tty || roles=""
  fi

  while :; do
    printf '참고할 위키/문서 디렉토리 (엔터=없음): '
    read -r wiki </dev/tty || wiki=""
    if [ -z "$wiki" ]; then break; fi
    wiki="${wiki/#\~/$HOME}"
    if [ -d "$wiki" ]; then break; fi
    printf '  그런 디렉토리가 없습니다: %s\n' "$wiki"
  done

  printf '에이전트 수 [4]: '
  read -r n </dev/tty || n=""
  if [ -z "$n" ]; then n=4; fi
  case "$n" in (*[!0-9]*|'') printf '  숫자가 아니라 4로 합니다\n'; n=4 ;; esac

  printf '에이전트 모델 [%s]: ' "$WIZ_DEFAULT_MODEL"
  read -r model </dev/tty || model=""
  if [ -z "$model" ]; then model="$WIZ_DEFAULT_MODEL"; fi

  printf '오케스트레이터 모델 [%s]: ' "$WIZ_DEFAULT_LEAD"
  read -r lead </dev/tty || lead=""
  if [ -z "$lead" ]; then lead="$WIZ_DEFAULT_LEAD"; fi

  WIZ_CMD=$(wizard_build_cmd "$team" "$wiki" "$n" "$model" "$lead")
  if [ -n "$roles" ]; then WIZ_CMD="$WIZ_CMD --roles $roles"; fi

  printf '\n실행: %s\n' "$WIZ_CMD"
  printf '진행할까요? [Y/n] '
  read -r ans </dev/tty || ans=y
  case "$ans" in [nN]*) return 1 ;; esac
  return 0
}
EOF
```

- [ ] **Step 4: 통과 확인**

Run: `bash ~/.config/herdr/orch/tests/run.sh`
Expected: 전부 통과

- [ ] **Step 5: orch 진입점 연결**

인자 파싱 while 루프 **앞**, `skill` 서브커맨드 분기 **뒤**에 둔다.

```bash
if [ $# -eq 0 ] && [ -t 0 ] && [ -z "${ORCH_NO_WIZARD:-}" ]; then
  . "$PROMPT_DIR/lib/wizard.sh"
  if wizard_run; then
    eval "exec $WIZ_CMD"
  else
    echo "취소했습니다."
    exit 0
  fi
fi
```

`[ -t 0 ]` 로 tty 가 없으면(파이프·스크립트) 마법사를 건너뛴다. `ORCH_NO_WIZARD=1` 은 테스트용 탈출구다.

- [ ] **Step 6: 비대화형 호환 확인**

```bash
echo "" | ORCH_CLAUDE_CMD="echo x" orch --list-teams | head -3
ORCH_NO_WIZARD=1 orch --help | head -3
```

Expected: 둘 다 마법사 없이 즉시 동작

- [ ] **Step 7: 마법사 흐름 확인**

입력을 주입해 생성되는 명령을 본다. 실제 팬은 만들지 않는다.

```bash
printf '2\n\n3\n\n\nn\n' | bash -c '
  . ~/.config/herdr/orch/lib/wizard.sh
  wizard_run || true
  echo "생성된 명령: $WIZ_CMD"
' < /dev/tty 2>/dev/null || echo "(tty 필요 — 터미널에서 직접 확인)"
```

Expected: `생성된 명령: orch 3 --team analysis`

- [ ] **Step 8: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add lib/wizard.sh tests/test_wizard.sh orch
git commit -m "feat: 인자 없이 실행 시 대화형 마법사"
```

---

### Task 9: 팀 스펙 `skills` 필드

**Files:**
- Modify: `/opt/homebrew/bin/orch` (`validate_spec` orch:139, 팀 생성 시 설치 루프, `orch skill add` 기록)
- Modify: `~/.config/herdr/orch/tests/test_skills.sh` (기록 함수 테스트 추가)
- Modify: `~/.config/herdr/orch/lib/skills.sh` (기록 함수 추가)

**Interfaces:**
- Consumes: Task 5의 `skill_add`, `skill_target_dir`
- Produces: `skill_record <spec_path> <역할명> <repo>` → 팀 JSON의 해당 역할 `skills` 배열에 추가(중복 무시). `skill_list_for_spec <spec_path>` → 스펙 전체의 repo 목록을 한 줄에 하나씩

설치한 스킬이 그 세션에서만 살아 있으면, 같은 팀을 다시 띄울 때 에이전트가 다시 막힌다.
설치 결과를 팀 프리셋에 남겨 다음 생성 때 자동으로 깔리게 한다. `mcp`/`plugins` 와 같은 패턴이다.

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/test_skills.sh` 의 `summary` 호출 **앞**에 삽입한다.

```bash
python3 - <<'EOF'
p="$HOME/.config/herdr/orch/tests/test_skills.sh"
s=open(p,encoding="utf-8").read()
add = """
SPEC=$(mktemp)
cat > "$SPEC" <<'JSON'
{"name":"테스트팀","roles":[
  {"name":"연구원","en":"researcher","prompt":"p","mcp":[],"plugins":[]},
  {"name":"구현","en":"builder","prompt":"p","mcp":[],"plugins":[],"skills":["a/b"]}]}
JSON

skill_record "$SPEC" "연구원" "vercel-labs/skills"
assert_eq "vercel-labs/skills" "$(jq -r '.roles[0].skills[0]' "$SPEC")" "skills 배열이 없으면 만들어서 넣는다"

skill_record "$SPEC" "구현" "c/d"
assert_eq "2" "$(jq -r '.roles[1].skills | length' "$SPEC")" "기존 배열에는 덧붙인다"

skill_record "$SPEC" "구현" "a/b"
assert_eq "2" "$(jq -r '.roles[1].skills | length' "$SPEC")" "같은 걸 또 넣어도 늘지 않는다"

skill_record "$SPEC" "없는역할" "x/y" 2>/dev/null && r=0 || r=1
assert_eq "1" "$r" "없는 역할이면 실패한다"

assert_eq "a/b
c/d
vercel-labs/skills" "$(skill_list_for_spec "$SPEC" | sort)" "스펙 전체의 repo 를 모은다"
rm -f "$SPEC"

"""
s = s.replace("\nsummary", add + "summary")
open(p,"w",encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: 실패 확인**

Run: `bash ~/.config/herdr/orch/tests/test_skills.sh`
Expected: FAIL — `skill_record: command not found`

- [ ] **Step 3: 구현**

```bash
cat >> ~/.config/herdr/orch/lib/skills.sh <<'EOF'

# 설치한 스킬을 팀 스펙에 기록한다. 같은 항목은 중복으로 넣지 않는다.
# 역할명이 스펙에 없으면 1을 돌려준다 — 조용히 넘어가면 기록이 유실된다.
skill_record() { # <spec_path> <역할명> <repo>
  local spec="$1" role="$2" repo="$3" tmp hit
  [ -f "$spec" ] || return 1
  hit=$(jq -r --arg r "$role" '[.roles[]? | select(.name == $r)] | length' "$spec")
  [ "$hit" -gt 0 ] || return 1
  tmp=$(mktemp)
  jq --arg r "$role" --arg s "$repo" '
    .roles = (.roles | map(
      if .name == $r
      then .skills = (((.skills // []) + [$s]) | unique)
      else . end))' "$spec" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$spec"
}

skill_list_for_spec() { # <spec_path>
  [ -f "$1" ] || return 0
  jq -r '[.roles[]?.skills // []] | flatten | unique | .[]' "$1" 2>/dev/null
}
EOF
```

`unique` 가 정렬까지 하므로 배열 순서는 알파벳순이 된다. 기록용이라 문제되지 않는다.

- [ ] **Step 4: 통과 확인**

Run: `bash ~/.config/herdr/orch/tests/run.sh`
Expected: 전부 통과

- [ ] **Step 5: `validate_spec` 에 skills 를 선택 필드로 추가**

orch:139 의 `validate_spec()` 안, 역할 순회 루프에 넣는다. 배열이 아니면 거른다.

```bash
    v=$(jq -r --argjson i "$i" '.roles[$i].skills // [] | if type == "array" then "ok" else "bad" end' "$f")
    if [ "$v" = "bad" ]; then
      echo "  역할 $((i+1)): skills 는 배열이어야 합니다" >&2
      bad=1
    fi
```

- [ ] **Step 6: 팀 생성 시 기록된 스킬을 자동 설치**

에이전트 팬 생성 루프(orch:935 부근, `build_agent_prompt` 호출 앞)보다 앞에 둔다.
스킬은 팬마다가 아니라 팀 cwd 에 한 번만 깔면 된다.

```bash
if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  . "$PROMPT_DIR/lib/skills.sh"
  PRESET_SKILLS=$(skill_list_for_spec "$SPEC")
  if [ -n "$PRESET_SKILLS" ]; then
    echo "팀 프리셋에 기록된 스킬을 설치합니다..."
    for sk in $PRESET_SKILLS; do
      if skill_add "${CWD:-$PWD}" "$sk" >/dev/null 2>&1; then
        echo "  설치: $sk"
      else
        echo "  실패(건너뜀): $sk" >&2
      fi
    done
  fi
fi
```

설치 실패가 팀 생성 전체를 막지 않게 한다 — 네트워크가 없어도 팀은 떠야 한다.

- [ ] **Step 7: `orch skill add` 가 기록하도록 연결**

Task 5의 `add` 분기에서 설치 성공 직후, 재구축 앞에 넣는다.

```bash
      if [ -n "$SK_ROLE" ]; then
        SK_SPEC=$(printf '%s' "$SK_STATE" | jq -r '.teams[0].spec // ""')
        if [ -n "$SK_SPEC" ] && [ -f "$SK_SPEC" ]; then
          if skill_record "$SK_SPEC" "$SK_ROLE" "$REPO"; then
            echo "팀 프리셋에 기록: $SK_SPEC ($SK_ROLE)"
          else
            echo "프리셋에 '$SK_ROLE' 역할이 없어 기록은 건너뜁니다" >&2
          fi
        fi
      fi
```

기록 실패가 설치를 되돌리지 않는다. 스킬은 이미 깔렸고 재구축하면 쓸 수 있다.

- [ ] **Step 8: 왕복 검증**

```bash
STUB=$(mktemp -d)
cat > "$STUB/npx" <<'EOF'
#!/bin/bash
if [ "$2" = "add" ]; then mkdir -p ".claude/skills/$(basename "$3")"; exit 0; fi
exit 0
EOF
chmod +x "$STUB/npx"
cp ~/.config/herdr/orch/teams/qa.json /tmp/qa-test.json
bash -c ". ~/.config/herdr/orch/lib/skills.sh
  skill_record /tmp/qa-test.json 자동화 'vercel-labs/skills'
  skill_list_for_spec /tmp/qa-test.json"
jq '.roles[] | select(.name=="자동화") | .skills' /tmp/qa-test.json
rm -f /tmp/qa-test.json; rm -rf "$STUB"
```

Expected: `["vercel-labs/skills"]` 가 자동화 역할에 기록됨

- [ ] **Step 9: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add lib/skills.sh tests/test_skills.sh orch
git commit -m "feat: 설치한 스킬을 팀 프리셋에 기록하고 다음 생성 때 자동 설치"
```

---

### Task 10: 문서 갱신과 최종 검증

**Files:**
- Modify: `/opt/homebrew/bin/orch` (헤더 주석 사용법)
- Modify: `~/.config/herdr/orch/USAGE.md`
- Modify: `/opt/homebrew/bin/orch` (`--doctor` 에 npx 점검 추가)

- [ ] **Step 1: 헤더 사용법 갱신**

orch 상단 주석(2-36행)에 새 플래그를 추가한다. `-h` 가 이 범위를 그대로 출력하므로 행 번호가 바뀌면 `sed -n '2,36p'` 도 함께 고쳐야 한다.

```
#   orch                     인자 없이 실행하면 대화형으로 물어본다
#   orch skill find <키워드> 에이전트에 넣을 스킬을 찾는다
#   orch skill add <repo> --role <역할>  설치하고 그 역할만 재기동
#   orch skill list          설치된 스킬 목록
#   orch --add-team <용도>   같은 워크스페이스 새 탭에 팀을 하나 더 만든다
#   orch --tab <라벨>        대상 팀을 탭으로 지정 (--stop/--reharness)
#   orch --all-teams         워크스페이스의 모든 팀을 대상으로
#   orch --reharness --only <역할>  특정 역할만 재구축
```

추가한 줄 수만큼 `-h|--help` 의 `sed -n '2,36p'` 범위를 늘린다.

- [ ] **Step 2: `--doctor` 에 npx 점검 추가**

```bash
if command -v npx >/dev/null 2>&1; then
  echo "  npx: $(command -v npx)"
else
  echo "  npx: 없음 — orch skill 명령을 쓸 수 없습니다 (node 설치 필요)"
fi
```

- [ ] **Step 3: USAGE.md 갱신**

새 기능 3종의 사용례를 추가한다.

```bash
cat >> ~/.config/herdr/orch/USAGE.md <<'EOF'

## 대화형으로 시작하기

```
orch
```

인자 없이 치면 용도·위키·에이전트 수·모델을 차례로 묻고, 실행할 명령을 보여준 뒤 확인받는다.
플래그를 하나라도 주면 예전처럼 즉시 실행한다.

## 운영 중 에이전트 업그레이드

에이전트가 능력이 모자라 막혔을 때 스킬을 넣어준다.

```
orch skill find pdf                        후보 검색
orch skill add vercel-labs/skills --role 연구원   설치 + 그 역할만 재기동
orch skill list                            설치된 목록
```

설치는 팀 작업 디렉토리의 `.claude/skills/` 로 격리되고, `--role` 을 주면
그 팬만 `--resume` 으로 재기동되므로 대화 맥락이 유지된다.

## 팀 증설

같은 워크스페이스에 새 탭을 만들어 독립 팀을 하나 더 띄운다.

```
orch 4 --add-team 분석            새 탭 'orch-analysis' 에 분석팀
orch 4 --add-team qa --name 검증  탭 이름을 직접 지정
```

각 팀은 자체 오케스트레이터를 갖고, 팀 간에는 오케↔오케로만 통신한다.
정리할 때는 대상을 지정해야 한다.

```
orch --stop --tab orch-analysis   그 팀만 정리
orch --stop --all-teams           워크스페이스의 모든 팀 정리
```
EOF
```

- [ ] **Step 4: 전체 테스트**

```bash
bash ~/.config/herdr/orch/tests/run.sh
bash -n /opt/homebrew/bin/orch && echo "문법 OK"
orch --doctor
orch --list-teams
```

Expected: 테스트 전부 통과, 문법 OK, doctor 에 npx 줄이 보임, 팀 10개

- [ ] **Step 5: 실제 워크스페이스로 끝까지 한 번**

```bash
WSID=$(herdr workspace create --label orch-final --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id')
ORCH_CLAUDE_CMD="echo x" orch 3 --workspace "$WSID" --team planning --cwd /tmp
ORCH_CLAUDE_CMD="echo x" orch 3 --workspace "$WSID" --add-team qa --cwd /tmp
jq '{v:.version, teams:[.teams[]|{tab_label,team,roles:(.roles|length)}]}' ~/.config/herdr/orch/state/$WSID.json
orch --reharness --dry-run --tab orch-qa --workspace "$WSID" | tail -5
orch --stop --all-teams --workspace "$WSID" --force
herdr workspace close "$WSID"
```

Expected: 팀 2개가 각각 기록되고, dry-run 이 qa 팀 팬만 보여주고, 정리 후 워크스페이스가 닫힘

- [ ] **Step 6: 커밋**

```bash
cd ~/.config/herdr/orch
cp /opt/homebrew/bin/orch ./orch
git add -A
git commit -m "docs: 새 기능 사용법 반영, doctor 에 npx 점검 추가"
```

---

## 되돌리기

각 태스크가 독립 커밋이므로 문제가 생기면 그 커밋만 되돌린다. 실행 파일은 저장소 밖이므로
되돌린 뒤 반드시 다시 복사해야 한다.

```bash
cd ~/.config/herdr/orch
git revert <commit>
cp ./orch /opt/homebrew/bin/orch
```

Task 3 이전으로 완전히 돌아가야 하면 백업을 쓴다.

```bash
cp ~/.config/herdr/orch/orch.bak.<날짜> /opt/homebrew/bin/orch
```

state 파일은 v2 로 승격된 뒤에도 구형 orch 가 읽으면 `orch_pane` 이 없어 reharness 가
실패한다. 되돌릴 때는 `state/` 를 비우고 팀을 다시 만드는 편이 빠르다.

#!/usr/bin/env bash
# orch 설치 스크립트 — bin/*를 PATH에, config/*를 ~/.config/herdr/orch/ 에 놓는다.
# 기존 파일은 덮어쓰기 전에 물어본다. --uninstall 로 되돌린다.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/orch"
FORCE=""; UNINSTALL=""; BINDIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --force)     FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --bindir)    BINDIR="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
사용법: ./install.sh [옵션]
  --bindir DIR   실행파일 설치 위치 (기본: 자동 탐색)
  --force        확인 없이 덮어쓴다
  --uninstall    설치한 것을 지운다
EOF
      exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }

# ── bin 디렉토리 결정 ────────────────────────────────
pick_bindir() {
  [ -n "$BINDIR" ] && { printf '%s' "$BINDIR"; return; }
  local c
  for c in "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
    case ":$PATH:" in *":$c:"*) [ -d "$c" ] && [ -w "$c" ] && { printf '%s' "$c"; return; } ;; esac
  done
  # PATH에 쓸 수 있는 후보가 없으면 ~/.local/bin 을 만들고 안내한다
  printf '%s' "$HOME/.local/bin"
}
BIN="$(pick_bindir)"

# ── 제거 ─────────────────────────────────────────────
if [ -n "$UNINSTALL" ]; then
  for f in orch orch-msg orch-snapshot orch-dash; do
    [ -e "$BIN/$f" ] && { rm -f "$BIN/$f"; say "지움: $BIN/$f"; }
  done
  for f in orchestrator.md agent.md planner.md admin.md snapshot.py; do
    [ -e "$CFG/$f" ] && { rm -f "$CFG/$f"; say "지움: $CFG/$f"; }
  done
  for d in teams guides lib dash; do
    if [ -d "$SRC/config/$d" ]; then
      for f in "$SRC/config/$d"/*; do
        [ -e "$CFG/$d/$(basename "$f")" ] && rm -f "$CFG/$d/$(basename "$f")"
      done
    fi
  done
  say "완료. 직접 만든 프리셋과 state/ 는 남겨뒀습니다: $CFG"
  exit 0
fi

# ── 선행 조건 ────────────────────────────────────────
say "선행 조건 확인"
MISSING=""
for c in herdr claude jq; do
  if command -v "$c" >/dev/null 2>&1; then
    say "  ✅ $c"
  else
    say "  ❌ $c 없음"; MISSING="$MISSING $c"
  fi
done
if [ -n "$MISSING" ]; then
  warn "다음이 없습니다:$MISSING"
  warn "INSTALL.md 의 OS별 절차를 먼저 따르세요."
  [ -n "$FORCE" ] || die "중단합니다 (--force 로 무시 가능)"
fi

# bash 버전 (3.2 이상)
BV="${BASH_VERSINFO[0]:-0}"
[ "$BV" -ge 3 ] || die "bash 3.2 이상이 필요합니다 (현재 $BASH_VERSION)"

# ── 설치 ─────────────────────────────────────────────
mkdir -p "$BIN" "$CFG/teams" "$CFG/guides" "$CFG/dash"

copy() { # <src> <dst>
  local s="$1" d="$2"
  if [ -e "$d" ] && [ -z "$FORCE" ]; then
    if cmp -s "$s" "$d"; then return 0; fi
    printf '  덮어쓸까요? %s [y/N] ' "$d"
    read -r a </dev/tty || a=n
    case "$a" in [yY]*) ;; *) say "  건너뜀: $d"; return 0 ;; esac
  fi
  cp "$s" "$d"
}

say ""
say "실행파일 → $BIN"
for f in orch orch-msg orch-snapshot orch-dash; do
  copy "$SRC/bin/$f" "$BIN/$f"
  chmod +x "$BIN/$f"
  say "  ✅ $f"
done

say ""
say "설정 → $CFG"
for f in orchestrator.md agent.md planner.md admin.md snapshot.py; do
  [ -f "$SRC/config/$f" ] && { copy "$SRC/config/$f" "$CFG/$f"; say "  ✅ $f"; }
done
for d in teams guides lib dash; do
  for f in "$SRC/config/$d"/*; do
    [ -f "$f" ] || continue
    copy "$f" "$CFG/$d/$(basename "$f")"
    say "  ✅ $d/$(basename "$f")"
  done
done

# ── PATH 안내 ────────────────────────────────────────
case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    say ""
    warn "$BIN 이 PATH에 없습니다. 셸 설정에 추가하세요:"
    say "    export PATH=\"$BIN:\$PATH\""
    ;;
esac

# ── 권한 허용 목록 (선택) ────────────────────────────
SETTINGS="$HOME/.claude/settings.json"
say ""
say "에이전트가 herdr 명령을 쓸 때마다 승인을 물으면 오케스트레이션이 멈춥니다."
say "통신·조회 명령을 $SETTINGS 의 허용 목록에 추가할까요?"
say "  (pane run·close 같은 실행·파괴 계열은 일부러 제외합니다)"
printf '추가할까요? [y/N] '
if [ -n "$FORCE" ]; then a=y; else read -r a </dev/tty || a=n; fi
case "$a" in
  [yY]*)
    if ! command -v python3 >/dev/null 2>&1; then
      warn "python3 이 없어 건너뜁니다. docs/PERMISSIONS.md 를 보고 직접 넣으세요."
    else
      python3 - "$SETTINGS" <<'PY'
import json, os, sys, shutil
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
d = {}
if os.path.exists(p):
    shutil.copy(p, p + ".bak")
    try:
        d = json.load(open(p))
    except Exception:
        print("  기존 settings.json 을 파싱하지 못해 건너뜁니다 (백업: %s.bak)" % p); sys.exit(0)
allow = [
  "Bash(herdr agent list)", "Bash(herdr agent get:*)", "Bash(herdr agent read:*)",
  "Bash(herdr agent send:*)", "Bash(herdr agent wait:*)", "Bash(herdr agent rename:*)",
  "Bash(herdr agent focus:*)", "Bash(herdr pane list:*)", "Bash(herdr pane get:*)",
  "Bash(herdr pane read:*)", "Bash(herdr pane layout:*)", "Bash(herdr pane rename:*)",
  "Bash(herdr pane focus:*)", "Bash(herdr pane zoom:*)", "Bash(herdr pane split:*)",
  "Bash(herdr pane send-text:*)", "Bash(herdr pane send-keys:*)",
  "Bash(herdr tab list:*)", "Bash(herdr tab create:*)", "Bash(herdr tab rename:*)",
  "Bash(herdr workspace list)", "Bash(herdr wait:*)", "Bash(herdr notification show:*)",
  "Bash(orch-msg:*)", "Bash(orch --status:*)", "Bash(orch --list-teams)", "Bash(orch --dashboard:*)",
]
cur = d.setdefault("permissions", {}).setdefault("allow", [])
added = [a for a in allow if a not in cur]
cur.extend(added)
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print("  ✅ %d건 추가 (백업: %s.bak)" % (len(added), p))
PY
    fi
    ;;
  *) say "  건너뜀. 나중에 docs/PERMISSIONS.md 참조." ;;
esac

say ""
say "설치 완료."
say ""
say "  orch --list-teams          팀 프리셋 확인"
say "  herdr                      herdr 실행"
say "  orch 4 --team dev          herdr 팬 안에서 팀 생성"
say ""
say "Windows 사용자는 INSTALL.md 의 WSL2 절차를 확인하세요."

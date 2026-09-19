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
  local base probe rest real
  base=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  # 설치 경로는 아직 없을 수 있다. 존재하는 조상까지 올라가 거기서 정규화한 뒤
  # 나머지를 도로 붙인다 — 그냥 문자열로 비교하면 macOS 의 /var → /private/var
  # 심볼릭 링크 때문에 같은 위치가 다르게 보인다.
  probe="$2"
  rest=""
  while [ -n "$probe" ] && [ "$probe" != "/" ] && [ ! -d "$probe" ]; do
    rest="$(basename "$probe")${rest:+/$rest}"
    probe="$(dirname "$probe")"
  done
  [ -d "$probe" ] || return 1
  real=$(cd "$probe" 2>/dev/null && pwd -P) || return 1
  if [ -n "$rest" ]; then real="$real/$rest"; fi
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

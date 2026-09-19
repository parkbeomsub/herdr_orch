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

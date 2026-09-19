#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(orch_lib state.sh)"

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

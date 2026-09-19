#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(orch_lib state.sh)"

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

#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(orch_lib wizard.sh)"

assert_eq "dev" "$(wizard_purpose_to_team 1)" "1번은 개발팀"
assert_eq "analysis" "$(wizard_purpose_to_team 2)" "2번은 분석팀"
assert_eq "planning" "$(wizard_purpose_to_team 3)" "3번은 기획팀"
assert_eq "qa" "$(wizard_purpose_to_team 4)" "4번은 테스트팀"
assert_eq "" "$(wizard_purpose_to_team 5)" "5번(기타)은 팀이 없다"
assert_eq "__self__" "$(wizard_purpose_to_team 6)" "6번은 orch 관리 세션"
assert_eq "dev" "$(wizard_purpose_to_team 개발)" "한글 이름도 받는다"
assert_eq "__self__" "$(wizard_purpose_to_team 관리)" "한글 '관리'도 받는다"

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

C=$(wizard_build_cmd "__self__" "" "4" "opus" "claude-opus-5[1m]")
assert_eq "orch --self" "$C" "관리 세션은 다른 플래그 없이 --self 만 쓴다"

summary

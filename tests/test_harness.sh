#!/bin/bash
. "$(dirname "$0")/helpers.sh"
assert_eq "a" "a" "같은 문자열은 통과한다"
assert_contains "hello world" "world" "부분 문자열을 찾는다"
assert_fail "없는 명령은 실패한다" false
summary

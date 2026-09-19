#!/bin/bash
# 테스트 어서션. bash 3.2 호환.
# lib 위치는 두 가지다 — 설치본은 ../lib, 저장소는 ../config/lib.
orch_lib() { # <파일명>
  local d="$(dirname "$0")/../lib"
  [ -d "$d" ] || d="$(dirname "$0")/../config/lib"
  printf '%s/%s' "$d" "$1"
}

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

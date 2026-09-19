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

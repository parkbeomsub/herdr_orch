#!/bin/bash
# 대시보드 데이터 가공 테스트 — herdr 없이 돈다
set -uo pipefail
. "$(dirname "$0")/helpers.sh"
. "$(orch_lib dash.sh)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── 정상 로그 ────────────────────────────────────────
cat > "$TMP/log.md" <<'EOF'
# 에이전트 통신 로그

| 2026-09-19 10:00:01 | 오케스트레이터 | PM | 요구사항 정리해주세요 |
| 2026-09-19 10:01:02 | PM | 오케스트레이터 | 정리했습니다 |
| 2026-09-19 10:02:03 | 오케스트레이터 | PM | 확인했습니다 |
EOF

OUT=$(dash_parse_log "$TMP/log.md")
assert_eq "3" "$(printf '%s' "$OUT" | jq 'length')" "메시지 3건을 읽는다"
assert_eq "오케스트레이터" "$(printf '%s' "$OUT" | jq -r '.[0].from')" "보낸이를 뽑는다"
assert_eq "PM" "$(printf '%s' "$OUT" | jq -r '.[0].to')" "받는이를 뽑는다"
assert_eq "요구사항 정리해주세요" "$(printf '%s' "$OUT" | jq -r '.[0].body')" "본문을 뽑는다"
assert_eq "2026-09-19 10:00:01" "$(printf '%s' "$OUT" | jq -r '.[0].ts')" "시각을 뽑는다"

# ── 본문에 | 가 들어간 경우 ───────────────────────────
# 에이전트는 표나 셸 파이프를 그대로 보낸다. 앞 3필드만 자르지 않으면 본문이 잘린다.
cat > "$TMP/pipe.md" <<'EOF'
| 2026-09-19 11:00:00 | 테크리드 | 풀스택 | ps aux | grep node 로 확인했습니다 |
EOF
OUT=$(dash_parse_log "$TMP/pipe.md")
assert_eq "1" "$(printf '%s' "$OUT" | jq 'length')" "파이프가 있어도 1건"
assert_contains "$(printf '%s' "$OUT" | jq -r '.[0].body')" "grep node" "본문의 | 뒤가 안 잘린다"

# ── 표 구분선·헤더는 메시지가 아니다 ──────────────────
cat > "$TMP/hdr.md" <<'EOF'
| 시각 | 보낸이 | 받는이 | 내용 |
|------|--------|--------|------|
| 2026-09-19 12:00:00 | QA | 오케스트레이터 | 테스트 통과 |
EOF
OUT=$(dash_parse_log "$TMP/hdr.md")
assert_eq "1" "$(printf '%s' "$OUT" | jq 'length')" "헤더와 구분선을 건너뛴다"
assert_eq "QA" "$(printf '%s' "$OUT" | jq -r '.[0].from')" "실제 행만 남는다"

# ── 없는 파일 ────────────────────────────────────────
assert_eq "[]" "$(dash_parse_log "$TMP/없는파일.md")" "없는 로그는 빈 배열"

# ── limit ────────────────────────────────────────────
: > "$TMP/many.md"
for i in 1 2 3 4 5; do
  echo "| 2026-09-19 13:00:0$i | A | B | 메시지$i |" >> "$TMP/many.md"
done
OUT=$(dash_parse_log "$TMP/many.md" 2)
assert_eq "2" "$(printf '%s' "$OUT" | jq 'length')" "limit 만큼만 남긴다"
assert_eq "메시지5" "$(printf '%s' "$OUT" | jq -r '.[-1].body')" "최근 것을 남긴다"

# ── 간선 합치기 ──────────────────────────────────────
MSGS='[{"from":"A","to":"B"},{"from":"B","to":"A"},{"from":"A","to":"B"},{"from":"A","to":"C"}]'
E=$(dash_edges "$MSGS")
assert_eq "2" "$(printf '%s' "$E" | jq 'length')" "쌍 2개로 합쳐진다"
assert_eq "3" "$(printf '%s' "$E" | jq -r '.[0].count')" "A↔B 는 방향 무시하고 3건"
assert_eq "1" "$(printf '%s' "$E" | jq -r '.[1].count')" "A↔C 는 1건"

summary

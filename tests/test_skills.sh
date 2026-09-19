#!/bin/bash
. "$(dirname "$0")/helpers.sh"
. "$(orch_lib skills.sh)"

skill_is_repo "vercel-labs/skills" && r=0 || r=1
assert_eq "0" "$r" "owner/repo 는 repo 로 본다"
skill_is_repo "vercel-labs/skills#pdf-extract" && r=0 || r=1
assert_eq "0" "$r" "owner/repo#skill 도 repo 로 본다"
skill_is_repo "pdf 추출" && r=0 || r=1
assert_eq "1" "$r" "공백이 있으면 키워드다"
skill_is_repo "typescript" && r=0 || r=1
assert_eq "1" "$r" "슬래시가 없으면 키워드다"
skill_is_repo "a/b/c" && r=0 || r=1
assert_eq "1" "$r" "슬래시가 둘이면 repo 가 아니다"

assert_eq "/tmp/proj/.claude/skills" "$(skill_target_dir /tmp/proj)" "설치 경로는 cwd 하위 .claude/skills"

TP=$(mktemp -d)
mkdir -p "$TP/proj"
skill_guard_path "$TP/proj" "$TP/proj/.claude/skills/x" && r=0 || r=1
assert_eq "0" "$r" "cwd 하위 경로는 통과한다"
skill_guard_path "$TP/proj" "$HOME/.claude/skills/x" && r=0 || r=1
assert_eq "1" "$r" "전역 경로는 막는다"
mkdir -p "$TP/other"
skill_guard_path "$TP/proj" "$TP/proj/../other/x" && r=0 || r=1
assert_eq "1" "$r" "상위로 빠져나가는 경로는 막는다"
rm -rf "$TP"

TMP=$(mktemp -d)
mkdir -p "$TMP/.claude/skills/alpha" "$TMP/.claude/skills/beta"
assert_eq "alpha
beta" "$(skill_installed "$TMP")" "설치된 스킬을 나열한다"
assert_eq "" "$(skill_installed /tmp/nonexistent-$$)" "없는 디렉토리는 빈 목록이다"
rm -rf "$TMP"

SPEC=$(mktemp)
cat > "$SPEC" <<'JSON'
{"name":"테스트팀","roles":[
  {"name":"연구원","en":"researcher","prompt":"p","mcp":[],"plugins":[]},
  {"name":"구현","en":"builder","prompt":"p","mcp":[],"plugins":[],"skills":["a/b"]}]}
JSON

skill_record "$SPEC" "연구원" "vercel-labs/skills"
assert_eq "vercel-labs/skills" "$(jq -r '.roles[0].skills[0]' "$SPEC")" "skills 배열이 없으면 만들어서 넣는다"

skill_record "$SPEC" "구현" "c/d"
assert_eq "2" "$(jq -r '.roles[1].skills | length' "$SPEC")" "기존 배열에는 덧붙인다"

skill_record "$SPEC" "구현" "a/b"
assert_eq "2" "$(jq -r '.roles[1].skills | length' "$SPEC")" "같은 걸 또 넣어도 늘지 않는다"

skill_record "$SPEC" "없는역할" "x/y" 2>/dev/null && r=0 || r=1
assert_eq "1" "$r" "없는 역할이면 실패한다"

assert_eq "a/b
c/d
vercel-labs/skills" "$(skill_list_for_spec "$SPEC" | sort)" "스펙 전체의 repo 를 모은다"
rm -f "$SPEC"

summary

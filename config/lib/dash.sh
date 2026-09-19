# dash.sh — 대시보드 데이터 가공 (순수 함수, herdr 호출 없음)
# orch-dash 가 source 한다. herdr 를 안 부르므로 테스트에서 단독 실행된다.

# orch-msg 가 쓰는 로그 한 줄: | 2026-08-17 03:23:07 | 보낸이 | 받는이 | 본문 |
# 본문에 | 가 들어갈 수 있으므로 앞 3개 필드만 자르고 나머지는 전부 본문으로 본다.
# 표 구분선(|---|---|)과 헤더 행은 건너뛴다.
dash_parse_log() { # <log_path> [limit]  → JSON 배열
  local f="$1" limit="${2:-200}"
  [ -f "$f" ] || { printf '[]'; return 0; }
  tail -400 "$f" | awk -v lim="$limit" '
    /^[ \t]*\|/ {
      n = split($0, f, "|")
      if (n < 5) next
      ts = f[2]; from = f[3]; to = f[4]
      gsub(/^[ \t]+|[ \t]+$/, "", ts)
      gsub(/^[ \t]+|[ \t]+$/, "", from)
      gsub(/^[ \t]+|[ \t]+$/, "", to)
      # 구분선(---), 빈 칸, 헤더 행은 메시지가 아니다
      if (ts ~ /^:?-+:?$/ || ts == "" || ts == "시각" || ts == "time") next
      # 시각 자리에 날짜가 없으면 메시지 행이 아니다
      if (ts !~ /[0-9]{2}:[0-9]{2}/) next
      # 행이 | 로 끝나면 split 이 마지막에 빈 필드를 만든다.
      # 그걸 그대로 이어붙이면 모든 본문 끝에 | 가 따라붙는다.
      last = n
      if (f[n] ~ /^[ \t]*$/) last = n - 1
      body = ""
      for (i = 5; i <= last; i++) body = body (i > 5 ? "|" : "") f[i]
      gsub(/^[ \t]+|[ \t]+$/, "", body)
      rows[++c] = ts "\x01" from "\x01" to "\x01" body
    }
    END {
      start = (c > lim ? c - lim + 1 : 1)
      for (i = start; i <= c; i++) print rows[i]
    }' \
  | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\u0001")
      | {ts: .[0], from: .[1], to: .[2], body: (.[3] // "")})'
}

# 방향을 무시하고 간선을 합친다 — A→B 와 B→A 는 같은 선이다.
# 합치지 않으면 두 겹이 겹쳐 그려져 굵기가 거짓말을 한다.
dash_edges() { # <messages_json> → [{from,to,count}] 내림차순
  printf '%s' "$1" | jq -c '
    map({pair: ([.from, .to] | sort), from: .from, to: .to})
    | group_by(.pair)
    | map({from: .[0].from, to: .[0].to, count: length})
    | sort_by(-.count)'
}

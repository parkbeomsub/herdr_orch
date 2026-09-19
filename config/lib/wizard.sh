#!/bin/bash
# 대화형 마법사. 답변을 기존 플래그로 번역하는 것이 전부다 —
# 새 실행 경로를 만들지 않으므로 플래그 사용자와 동작이 갈라지지 않는다.

WIZ_DEFAULT_MODEL="${ORCH_MODEL:-opus}"
WIZ_DEFAULT_LEAD="${ORCH_LEAD_MODEL:-claude-opus-5[1m]}"

# 팀 프리셋 이름을 돌려준다. 기타는 빈 문자열, orch 관리는 __self__ 센티널.
wizard_purpose_to_team() { # <번호|이름>
  case "$1" in
    1|개발|dev)      printf 'dev' ;;
    2|분석|analysis) printf 'analysis' ;;
    3|기획|planning) printf 'planning' ;;
    4|테스트|qa)     printf 'qa' ;;
    6|관리|self)     printf '__self__' ;;
    *)               printf '' ;;
  esac
}

# 실행할 명령줄을 문자열로 만든다. 기본값과 같은 항목은 플래그를 생략해
# 사용자가 화면에서 보는 명령이 짧고 읽기 쉽게 한다.
wizard_build_cmd() { # <team> <wiki> <n> <model> <lead>
  local team="$1" wiki="$2" n="$3" model="$4" lead="$5" cmd
  # 관리 세션은 팀이 아니라 팬 하나다 — 에이전트 수·위키·모델이 의미 없다
  if [ "$team" = "__self__" ]; then printf 'orch --self'; return 0; fi
  cmd="orch $n"
  if [ -n "$team" ]; then cmd="$cmd --team $team"; fi
  if [ -n "$wiki" ]; then cmd="$cmd --wiki $wiki"; fi
  if [ "$model" != "$WIZ_DEFAULT_MODEL" ]; then cmd="$cmd --model $model"; fi
  if [ "$lead" != "$WIZ_DEFAULT_LEAD" ]; then cmd="$cmd --orch-model $lead"; fi
  printf '%s' "$cmd"
}

# 대화형 질문. tty 가 없으면 호출하면 안 된다 (호출부가 판단한다).
wizard_run() { # 결과를 WIZ_CMD 에 담는다
  local purpose team wiki n model lead roles ans
  printf '\n무엇을 하려고 하나요?\n'
  printf '  1) 개발   — 기획·설계·구현·QA·배포를 한 팀에서\n'
  printf '  2) 분석   — 데이터 수집·검증·해석·시각화\n'
  printf '  3) 기획   — 문제 정의·사용자 검증·명세·우선순위\n'
  printf '  4) 테스트 — 테스트 설계·자동화·탐색·성능보안\n'
  printf '  5) 기타   — 역할을 직접 정한다\n'
  printf '  6) orch 관리 — orch 명령어 자체를 고도화·관리하는 세션\n'
  printf '선택 [1]: '
  read -r purpose </dev/tty || purpose=""
  if [ -z "$purpose" ]; then purpose=1; fi
  team=$(wizard_purpose_to_team "$purpose")

  # 관리 세션은 나머지를 물을 필요가 없다
  if [ "$team" = "__self__" ]; then
    WIZ_CMD="orch --self"
    printf '\n실행: %s\n' "$WIZ_CMD"
    printf '진행할까요? [Y/n] '
    read -r ans </dev/tty || ans=y
    case "$ans" in [nN]*) return 1 ;; esac
    return 0
  fi

  roles=""
  if [ -z "$team" ]; then
    printf '역할 이름을 쉼표로 적으세요 (예: 리서치,구현,검증): '
    read -r roles </dev/tty || roles=""
  fi

  while :; do
    printf '참고할 위키/문서 디렉토리 (엔터=없음): '
    read -r wiki </dev/tty || wiki=""
    if [ -z "$wiki" ]; then break; fi
    case "$wiki" in "~"/*) wiki="$HOME/${wiki#\~/}" ;; esac
    if [ -d "$wiki" ]; then break; fi
    printf '  그런 디렉토리가 없습니다: %s\n' "$wiki"
  done

  printf '에이전트 수 [4]: '
  read -r n </dev/tty || n=""
  if [ -z "$n" ]; then n=4; fi
  case "$n" in (*[!0-9]*|'') printf '  숫자가 아니라 4로 합니다\n'; n=4 ;; esac

  printf '에이전트 모델 [%s]: ' "$WIZ_DEFAULT_MODEL"
  read -r model </dev/tty || model=""
  if [ -z "$model" ]; then model="$WIZ_DEFAULT_MODEL"; fi

  printf '오케스트레이터 모델 [%s]: ' "$WIZ_DEFAULT_LEAD"
  read -r lead </dev/tty || lead=""
  if [ -z "$lead" ]; then lead="$WIZ_DEFAULT_LEAD"; fi

  WIZ_CMD=$(wizard_build_cmd "$team" "$wiki" "$n" "$model" "$lead")
  if [ -n "$roles" ]; then WIZ_CMD="$WIZ_CMD --roles $roles"; fi

  printf '\n실행: %s\n' "$WIZ_CMD"
  printf '진행할까요? [Y/n] '
  read -r ans </dev/tty || ans=y
  case "$ans" in [nN]*) return 1 ;; esac
  return 0
}

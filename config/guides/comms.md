# 팀 통신 — orch-msg

팬 사이 통신은 `orch-msg`로 한다. 이게 팀의 **영속 대화 기록**이다.

## 왜 herdr 명령을 직접 쓰지 않는가

`herdr agent send`는 입력만 하고 제출하지 않아서 `send-keys enter`가 따로 필요하고,
긴 메시지는 렌더가 끝나기 전에 enter가 도착하면 제출되지 않고 입력창에 남는다.
`orch-msg send`가 이 처리를 다 해준다. 그리고 **대화가 파일로 남는다.**

## 명령

```bash
orch-msg send <역할명> '<메시지>'    # 보내기 + 자동 기록. 한 방에 끝난다.
orch-msg log                          # 최근 30개 대화 읽기
orch-msg log --from 편집장            # 특정 사람이 보낸 것만
orch-msg log --grep 팩트체크          # 본문 검색
orch-msg who                          # 내 팀원 목록 (내 워크스페이스만)
orch-msg whoami                       # 내 역할·워크스페이스·로그 경로
```

## 규칙

1. **작업 완료·블로킹·질문은 `orch-msg send`로 보낸다.** 그래야 기록이 남아
   나중에 합류한 사람이나 재시작한 세션이 맥락을 복원할 수 있다.
2. **`orch-msg log --all`을 쓰지 마라.** 로그는 수천 줄까지 자란다.
   기본값(최근 30개)이나 `--grep`으로 필요한 것만 읽어라.
3. **역할명으로 보내도 안전하다.** `orch-msg`가 내 워크스페이스 안에서만 이름을 찾고,
   대상이 경계 밖이면 전송을 거부한다. `herdr agent send`와 달리 전역 검색을 하지 않는다.
4. 내 신원은 환경변수 `ORCH_ROLE` / `ORCH_WS` / `ORCH_PANE`에 있다.
   헷갈리면 `orch-msg whoami`.

## Agent Teams와의 구분

Claude Code의 Agent Teams(팀원·공유 태스크 리스트)는 **내 팬 안에서** 병렬 작업을 할 때 쓴다.
`orch-msg`는 **팬과 팬 사이** 통신이다. 둘은 다른 층이므로 섞지 마라.

- 내가 혼자 병렬로 조사할 일 → Agent Teams 팀원
- 옆 팬의 다른 역할에게 결과를 넘길 일 → `orch-msg send`

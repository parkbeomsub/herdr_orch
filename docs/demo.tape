# orch 데모 GIF — VHS 스크립트
#
# 렌더:  vhs docs/demo.tape     (brew install vhs)
#
# 녹화용 herdr 인스턴스를 --session 으로 분리한다. 기본 세션을 그대로 찍으면
# 사이드바에 녹화자의 실제 워크스페이스 이름이 전부 노출된다.
# 에이전트 부팅 대기(약 20초)는 Hide 로 건너뛴다 — 프레임만 늘고 볼 게 없다.
#
# 사전 준비:
#   mkdir -p /tmp/demo-app && cd /tmp/demo-app  (CLAUDE.md 등 데모용 파일)
#   Claude Code 폴더 신뢰를 미리 수락해 두지 않으면 팬마다 신뢰 확인에서 멈춘다.

Output "docs/demo.gif"

Set Shell "bash"
Set FontFamily "D2Coding"
Set FontSize 13
Set Width 1280
Set Height 760
Set Padding 12
Set Framerate 20
Set TypingSpeed 32ms

# herdr 팬 안에서 렌더링하면 중첩이 막히므로 환경변수를 지운다
Hide
Type "cd /tmp/demo-app && unset HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_SOCKET_PATH CLAUDE_CODE_CHILD_SESSION && clear" Enter
Type "herdr --session demo" Enter
Sleep 6s
Show

Sleep 1.2s

# ── 팀 생성 — 팬이 갈라지는 순간이 이 도구의 핵심 ──
Type "orch 4 --team dev"
Sleep 600ms
Enter
Sleep 6s

# 에이전트 부팅은 볼 게 없으니 건너뛴다
Hide
Sleep 22s
Show
Sleep 2.5s

# ── 실제로 일을 시킨다 ──
Type "결제 실패 재시도 로직을 설계해서 각자에게 분배해줘"
Sleep 800ms
Enter
Sleep 14s

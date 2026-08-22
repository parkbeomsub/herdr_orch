# orch 데모 GIF — VHS 스크립트
#
# 렌더:  vhs docs/demo.tape     (brew install vhs)
#
# 여기서는 **읽기 전용 명령만** 녹화한다. 이유 두 가지:
#  1) herdr TUI를 찍으면 사이드바에 녹화자의 실제 워크스페이스 이름이 노출된다.
#  2) 팀 생성을 녹화하면 실제 에이전트가 떠서 비용이 나가고, 워크스페이스 ID가 박힌다.
# 아래 세 명령은 어느 환경에서 돌려도 같은 성격의 결과가 나와 재현 가능하다.

Output docs/demo.gif

Set Shell "bash"
Set FontFamily "D2Coding"
Set FontSize 16
Set Width 1120
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 30ms

Hide
Type "clear" Enter
Show
Sleep 700ms

# ── 1) 설치가 제대로 됐는지 한 번에 점검 ──
Type "orch --doctor"
Sleep 500ms
Enter
Sleep 4s

Type "clear" Enter
Sleep 400ms

# ── 2) 어떤 팀들이 있나 ──
Type "orch --list-teams"
Sleep 400ms
Enter
Sleep 2.5s

# ── 3) 팀에 뭐가 들어있는지 띄우기 전에 확인 ──
Type "orch --show dev | head -20"
Sleep 500ms
Enter
Sleep 5s

Sleep 1.5s

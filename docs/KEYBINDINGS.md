# 단축키 설정

herdr 기본값은 tmux 스타일(`Ctrl+B` prefix)입니다. 에이전트를 여러 개 오가려면
**팬·탭·워크스페이스 이동을 prefix 없이** 쓰는 편이 훨씬 빠릅니다.

아래는 그 목적으로 정리한 설정이고, `config/herdr-config.toml`에 그대로 들어 있습니다.

---

## 빠른 적용

```bash
# 기존 설정이 있으면 백업
cp ~/.config/herdr/config.toml ~/.config/herdr/config.toml.bak 2>/dev/null

# 예시 설정 복사 (기존 설정과 병합하려면 [keys] 블록만 가져가세요)
cp config/herdr-config.toml ~/.config/herdr/config.toml

herdr config check          # 문법 확인
herdr server reload-config  # 실행 중인 서버에 적용 — 재시작 불필요
```

> `reload-config`를 안 하면 **적용되지 않습니다.** herdr는 파일 변경을 자동으로 읽지 않습니다.

---

## 키 배치

`prefix`는 `Ctrl+A`입니다 (GNU screen 스타일).

### 이동 — prefix 없이 (자주 씀)

| 동작 | 키 |
|---|---|
| **팬** 이동 | `Ctrl` + `←↑↓→` |
| **탭** 이동 | `Ctrl`+`Shift` + `←→` |
| **워크스페이스** 이동 | `Ctrl`+`Shift` + `↑↓` |

방향이 일관됩니다 — **좌우는 탭, 상하는 워크스페이스**, 수식키 없이 방향키만이면 팬입니다.

### 생성·이름변경 — prefix 경유 (가끔 씀)

| 동작 | 키 |
|---|---|
| 워크스페이스 생성 / 이름변경 | `Ctrl+A` `N` / `Ctrl+A` `Shift+I` |
| 탭 생성 / 이름변경 | `Ctrl+A` `T` / `Ctrl+A` `Shift+T` |
| 팬 이름변경 | `Ctrl+A` `Shift+N` |
| 팬 분할 (위아래 / 좌우) | `Ctrl+A` `-` / `Ctrl+A` `\` |
| 팬 닫기 | `Ctrl+A` `X` |
| 팬 확대/축소 | `Ctrl+A` `Z` |

`prefix`를 누르고 **뗀 뒤** 다음 키를 누릅니다. 동시에 누르는 게 아닙니다.

> **왜 탭 이동이 `Ctrl+Shift+←→`인가**: herdr 기본값은 `next_tab = prefix+n`인데,
> 위에서 `prefix+n`을 워크스페이스 생성으로 옮겼기 때문에 충돌합니다.
> 마찬가지로 팬 이름변경이 기본 `prefix+shift+p`가 아니라 `prefix+shift+n`인 것은,
> `prefix+shift+n`이 원래 `new_workspace`였다가 비었기 때문입니다.
> **기본값을 바꾸면 반드시 충돌을 확인하세요** — `herdr --default-config`로 전체 매핑을 볼 수 있습니다.

---

## ⚠️ 터미널이 키를 가로챕니다 — 여기가 진짜 함정

herdr 설정을 아무리 고쳐도 **터미널이 키를 안 넘기면 도달하지 않습니다.**
"설정했는데 안 먹는다"의 대부분이 이 문제입니다.

### 내 터미널이 뭘 보내는지 확인하는 법

```bash
cat -v
```

그 상태에서 키를 눌러보세요. 화면에 나오는 게 **herdr가 받는 것**입니다. `Ctrl+C`로 종료.

| 출력 | 의미 |
|---|---|
| `^[[1;5D` | Ctrl+Left — 잘 전달됨 |
| `^[[1;3D` | Alt/Option+Left — 잘 전달됨 |
| `^[[1;6D` | Ctrl+Shift+Left |
| `^[b` | **단어 이동으로 가로채짐** — herdr에 안 감 |
| `^[[D` | 그냥 Left — **수식키가 무시됨** |
| (아무것도 안 나옴) | OS나 터미널이 먹음 |

`^[b`나 `^[[D`가 나오면 그 조합은 herdr에서 쓸 수 없습니다. 터미널 설정을 고치거나 다른 조합을 쓰세요.

### macOS — iTerm2

iTerm2 기본 프로필은 **`Option+←/→`를 단어 이동(`b`/`f`)으로 매핑**해 두었습니다.
더 큰 문제는 `Option Key Sends = Normal` 설정인데, 이러면
**Option이 낀 조합 전체가 별개 키로 전송되지 않습니다** — `Ctrl+Option+←`가 그냥 `Ctrl+←`가 됩니다.

**Option을 쓰고 싶다면** Settings → Profiles → Keys 에서:
1. `Left Option Key`를 **`Esc+`** 로 변경
2. Key Mappings에서 기존 `⌥←`·`⌥→` 삭제
3. `+`로 4개 추가, Action은 전부 **Send Escape Sequence**:

| 키 | 시퀀스 |
|---|---|
| `⌥←` | `[1;3D` |
| `⌥→` | `[1;3C` |
| `⌥↑` | `[1;3A` |
| `⌥↓` | `[1;3B` |

대신 셸에서 `Option+←/→` 단어 이동을 잃습니다.

**그게 싫으면 `Ctrl+방향키`를 쓰세요** — iTerm2가 기본으로 `[1;5X`를 보내므로 설정 없이 됩니다.
이 저장소의 기본값이 그것입니다.

### macOS — Terminal.app

Option을 Meta로 쓰려면 **Settings → Profiles → Keyboard → "Use Option as Meta key"** 를 켜세요.
켜지 않으면 Option 조합이 특수문자로 들어갑니다.

### Linux — GNOME Terminal / Konsole 등

대부분 `Ctrl`·`Alt`+방향키를 CSI로 잘 보냅니다. 다만 **데스크톱 환경이 먼저 가로채는** 경우가 있습니다:

- GNOME: `Ctrl+Alt+←/→`가 **워크스페이스 전환**에 기본 배정돼 있습니다
  → Settings → Keyboard → Keyboard Shortcuts 에서 해제하거나 다른 조합을 쓰세요
- KDE: System Settings → Shortcuts 에서 동일하게 확인

`cat -v`로 아무것도 안 나오면 herdr가 아니라 **WM이 먹은 것**입니다.

### Linux — Alacritty / kitty / WezTerm

기본적으로 잘 전달합니다. kitty는 자체 키보드 프로토콜을 쓰므로 이상하면
`kitty_mod` 관련 설정을 확인하세요.

### Windows — WSL2 + Windows Terminal

Windows Terminal이 일부 조합을 **자기 액션에 먼저 배정**해 둡니다:

| 조합 | 기본 동작 |
|---|---|
| `Ctrl+Shift+←/→` | 없음 (통과) |
| `Ctrl+Shift+↑/↓` | 없음 (통과) |
| `Alt+←/→` | 없음 (통과) |
| `Ctrl+Shift+T`·`W`·`N` | **탭/창 조작에 배정됨** |

prefix 조합(`Ctrl+A` 후 `Shift+T` 등)은 prefix를 거치므로 대체로 안전하지만,
직접 조합이 안 먹으면 Windows Terminal의 **Settings → Actions**에서 해당 항목을 삭제하세요.

---

## 한글 입력을 쓴다면

macOS에서 한글 입력 상태일 때 prefix가 안 먹는 문제가 있습니다. 이 설정으로 해결됩니다:

```toml
[experimental]
# prefix 모드 동안 영문 자판으로 자동 전환 후 복원 (macOS 전용)
switch_ascii_input_source_in_prefix = true

# Claude Code처럼 자체 커서를 그리는 TUI에서
# 한글 조합 후보창이 커서를 따라오도록 커서를 외부 터미널에 노출
reveal_hidden_cursor_for_cjk_ime = true
cjk_ime_agents = ["claude"]
```

일본어·중국어 입력기도 같은 문제가 있으면 `cjk_ime_agents`에 해당 에이전트를 추가하세요.

---

## 확인

```bash
herdr config check        # config: ok 가 나와야 함
herdr server reload-config
```

`reload-config` 응답의 `diagnostics`가 비어 있으면 정상입니다.
충돌이 있으면 여기에 나옵니다.

바꾼 키를 실제로 눌러보고, 안 되면 **`cat -v`부터** 하세요 —
herdr 설정 문제인지 터미널 문제인지 그것으로 갈립니다.

---

## 전체 옵션 보기

```bash
herdr --default-config
```

여기 없는 동작(`goto`, `workspace_picker`, `resize_mode`, 인덱스 점프 등)도 많습니다.
사용자 정의 명령(`[[keys.command]]`)으로 팝업 실행도 걸 수 있습니다:

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "popup"
command = "lazygit"
width = "80%"
height = "80%"
```

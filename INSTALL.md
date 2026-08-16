# 설치 가이드

`orch`는 [herdr](https://herdr.dev) 위에서 도는 bash 스크립트입니다.
따라서 **herdr가 도는 곳이면 돌고, 안 도는 곳이면 안 됩니다.**

| OS | herdr | orch | 권장 경로 |
|---|---|---|---|
| **macOS** | 안정 | ✅ | Homebrew |
| **Linux** | 안정 | ✅ | 설치 스크립트 |
| **Windows** | **프리뷰 베타** | ⚠️ | **WSL2 안에서 Linux처럼** |

---

## 공통 선행 조건

세 가지가 PATH에 있어야 합니다.

```bash
herdr --version     # 0.7.5 이상
claude --version    # Claude Code
jq --version        # JSON 파싱
```

`bash`는 3.2 이상이면 됩니다 (macOS 기본 bash가 3.2라 그 기준으로 짰습니다).

---

## macOS

```bash
# 1) herdr
brew install herdr

# 2) jq
brew install jq

# 3) Claude Code — https://claude.com/claude-code 참조

# 4) orch
git clone https://github.com/<당신>/orch-kit.git
cd orch-kit
./install.sh
```

### ⚠️ iTerm2를 쓴다면 키 설정을 확인하세요

iTerm2는 기본 프로필에서 **`Option+←/→`를 단어 이동(`b`/`f`)으로 가로챕니다.**
게다가 `Option Key Sends = Normal`이면 **Option이 낀 조합 전체가 별개 키로 전송되지 않습니다** —
`Ctrl+Option+←`가 그냥 `Ctrl+←`가 되어버립니다.

herdr 키바인딩에 Option 조합을 쓸 거면 **Settings → Profiles → Keys**에서:
1. `Left Option Key`를 **`Esc+`** 로 변경
2. 기존 `⌥←`·`⌥→` 매핑 삭제
3. 4방향에 `Send Escape Sequence` → `[1;3D` / `[1;3C` / `[1;3A` / `[1;3B` 추가

귀찮으면 **`Ctrl+방향키`**를 쓰세요 — iTerm2가 기본으로 `[1;5X`를 보내므로 그냥 됩니다.

---

## Linux

```bash
# 1) herdr
curl -fsSL https://herdr.dev/install.sh | sh

# 2) jq
sudo apt install jq        # Debian/Ubuntu
sudo dnf install jq        # Fedora
sudo pacman -S jq          # Arch

# 3) Claude Code — https://claude.com/claude-code 참조

# 4) orch
git clone https://github.com/<당신>/orch-kit.git
cd orch-kit
./install.sh
```

Nix를 쓴다면 herdr는 flake로도 제공됩니다.

### 알려진 차이

스크립트는 GNU coreutils와 BSD 양쪽에서 동작하도록 썼지만, **개발·검증은 macOS(BSD)에서 했습니다.**
Linux에서 이상하면 [이슈](../../issues)를 열어주세요. 특히 다음이 의심 지점입니다:

| 명령 | 비고 |
|---|---|
| `date -r FILE` | GNU·BSD 모두 문서화돼 있고, 실패하면 시각 없이 파일명만 출력하도록 폴백을 넣어뒀습니다 |
| `column -t -s` | util-linux와 BSD column의 동작이 미묘하게 다를 수 있습니다 (표 정렬만 영향) |
| `paste -sd, -` | 양쪽 지원 |

---

## Windows

**결론부터: WSL2를 쓰세요.**

herdr는 Windows 빌드를 **프리뷰 베타**로만 제공합니다(공식 사이트 표기).
`orch`는 bash 스크립트라 PowerShell에서 직접 돌지 않습니다.

### 권장: WSL2 (Ubuntu)

```powershell
# PowerShell (관리자)
wsl --install -d Ubuntu
```

재부팅 후 Ubuntu 터미널에서 **위의 Linux 절차를 그대로** 따르면 됩니다.

```bash
curl -fsSL https://herdr.dev/install.sh | sh
sudo apt update && sudo apt install -y jq git
git clone https://github.com/<당신>/orch-kit.git
cd orch-kit && ./install.sh
```

**WSL 사용 시 주의:**

| 항목 | 내용 |
|---|---|
| **프로젝트 위치** | `/home/<user>/` 아래에 두세요. `/mnt/c/`는 파일 I/O가 몇 배 느려 에이전트가 파일을 많이 읽는 이 워크로드에서 체감됩니다 |
| **줄바꿈** | `git config --global core.autocrlf input` — CRLF가 섞이면 bash가 `\r` 때문에 스크립트를 못 읽습니다 |
| **터미널** | Windows Terminal을 쓰면 키 전달이 가장 무난합니다 |
| **Claude Code** | WSL 안에 설치하세요. Windows 쪽 설치본은 WSL의 `claude`가 아닙니다 |

### 대안: Git Bash / MSYS2 (비권장)

`orch` 스크립트 자체는 Git Bash에서 파싱은 되지만, **herdr Windows 빌드가 프리뷰**라 팬 제어 API 동작을 보장할 수 없습니다. 실험 목적이 아니면 WSL2를 쓰세요.

### 네이티브 PowerShell은 지원하지 않습니다

포팅하려면 `orch`·`orch-msg`를 PowerShell로 다시 써야 합니다.
관심 있으면 [이슈](../../issues)로 얘기해 주세요 — 현재 계획에는 없습니다.

---

## 설치 확인

```bash
orch --list-teams
```

팀 5개가 나오면 성공입니다.

```
content    컨텐츠팀 — 9개 역할
dev        개발팀 — 9개 역할
growth     그로스팀 — 9개 역할
marketing  마케팅팀 — 9개 역할
video      영상제작팀 — 9개 역할
```

그다음 herdr 안에서:

```bash
orch 4 --team dev --cwd ~/myproject
```

---

## 권한 설정 (중요)

에이전트가 `herdr` 명령을 쓸 때마다 승인을 물으면 **오케스트레이션이 멈춥니다.**
`install.sh`가 `~/.claude/settings.json`에 통신·조회 명령을 허용 목록으로 추가할지 물어봅니다.

**일부러 제외한 것:**

| 제외 | 이유 |
|---|---|
| `herdr pane run` | `pane run <팬> "<아무 명령>"`으로 **Bash 권한 검사를 우회**해 임의 코드 실행이 됩니다 |
| `pane close` · `workspace close` | 파괴적 |

즉 orch가 **새 에이전트를 띄우거나 팬을 닫을 때만** 승인을 묻습니다. 이게 의도된 안전장치입니다.

수동으로 넣으려면 [docs/PERMISSIONS.md](docs/PERMISSIONS.md)를 보세요.

---

## 제거

```bash
./install.sh --uninstall
```

`bin/` 링크와 `~/.config/herdr/orch/`의 설치 파일을 지웁니다.
직접 만든 팀 프리셋과 `state/`는 남깁니다.

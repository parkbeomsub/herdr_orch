# 안 될 때

실제로 겪은 문제들입니다. 위에서부터 흔한 순서입니다.

## `orch: command not found`

`install.sh`가 고른 bin 디렉토리가 PATH에 없는 경우입니다.

```bash
ls ~/.local/bin/orch          # 설치는 됐나
echo "$PATH" | tr ':' '\n'    # PATH에 있나
export PATH="$HOME/.local/bin:$PATH"   # 셸 설정(.zshrc/.bashrc)에 추가
```

## `herdr 서버를 찾지 못했습니다`

`orch`는 **herdr 안에서** 실행해야 합니다. herdr를 먼저 띄우고, 그 팬 안에서 치세요.

```bash
herdr                # 실행
herdr status server  # running 인지 확인
```

## `client protocol N is newer than server protocol M`

herdr 바이너리를 업그레이드했는데 **서버가 아직 옛 버전**입니다. 이 상태에서는 모든 CLI가 막힙니다.

```bash
# herdr 밖의 터미널에서 (herdr 팬 안에서 하면 자기 자신을 죽입니다)
HERDR_SOCKET_PATH=~/.config/herdr/herdr.sock herdr server stop
herdr
```

⚠️ **서버를 멈추면 팬 프로세스가 종료됩니다.** `resume_agents_on_restore`가 켜져 있으면 Claude 세션은 대화 기록과 함께 복원되지만, **진행 중이던 턴은 유실**됩니다. 에이전트들이 idle일 때 하세요.

## 재시작 후 에이전트 이름이 전부 `-` 로 나온다

herdr는 **팬 라벨은 유지하지만 agent 이름 등록은 잃습니다.** 라벨에서 복구하세요.

```bash
herdr pane list --workspace wX \
  | jq -r '.result.panes[] | select(.label != null) | "\(.pane_id)\t\(.label)"' \
  | while IFS=$'\t' read -r pid label; do
      slug=$(printf '%s' "$label" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-')
      herdr agent rename "$pid" "${slug:-agent}"
    done
```

`orch-msg`는 **팬 라벨로 대상을 찾으므로** 이름이 없어도 동작합니다. `orch --status`의 이름 칸만 비어 보입니다.

## `invalid_agent_name: agent name must start with a lowercase letter…`

herdr 0.7.5부터 agent 이름이 `[a-z][a-z0-9_-]{0,31}` 로 제한됩니다. **한글 역할명이 거부됩니다.**

`orch`는 이미 대응돼 있습니다 — 팬 라벨은 한글, agent 이름은 팀 프리셋의 `en` 슬러그를 씁니다.
직접 rename할 때만 영문 슬러그를 쓰세요.

## 메시지를 보냈는데 상대가 반응이 없다

**`agent send`는 입력만 하고 제출하지 않습니다.** Enter를 따로 보내야 합니다.

```bash
herdr agent send <pane> '내용'
herdr pane send-keys <pane> enter    # ← 이게 없으면 입력창에 남아 있다가
                                     #   다음 메시지와 합쳐집니다
```

`orch-msg send`는 이 두 단계를 알아서 합니다. 직접 herdr 명령을 쓸 때만 주의하세요.

**반환값이 `ok`여도 전달됐다는 뜻이 아닙니다.** 입력 자체는 성공했으니까요. 중요한 보고는 `comms/log.md`를 확인하고, 회신이 없으면 재전송하세요.

## `orch-msg: 워크스페이스를 알 수 없습니다`

herdr 팬 **밖에서** 실행했습니다. herdr는 팬 안에만 `HERDR_WORKSPACE_ID`를 주입합니다.

의도적으로 밖에서 쓰려면 직접 주세요:

```bash
ORCH_WS=wP ORCH_PANE=wP:p2 orch-msg who
```

> 포커스된 워크스페이스로 폴백하지 **않습니다.** 신원을 모르는 채 보내면
> 사용자가 지금 보고 있는 엉뚱한 스페이스로 메시지가 갑니다.

## 에이전트가 `blocked` 에서 안 움직인다

권한 승인 프롬프트에 걸린 것입니다. 팬 하단을 보세요:

| 표시 | 상태 |
|---|---|
| `⏵⏵ bypass permissions on` | 욜로 적용됨 (정상) |
| `⏸ manual mode on` | 승인 대기 — 여기서 멈춥니다 |

에이전트 팬은 기본이 `--dangerously-skip-permissions`입니다. `--no-yolo`로 껐다면 승인을 눌러줄 사람이 필요합니다.

## 에이전트가 다른 스페이스 팬에 메시지를 보냈다

`orch-msg`를 쓰지 않고 `herdr agent send <역할명>`을 직접 썼을 때 생깁니다.
**agent 이름은 herdr 전역에서 해석**되므로 다른 스페이스에 같은 이름이 있으면 그리로 갑니다.

항상 `orch-msg`를 쓰거나, 직접 쓸 거면 **pane_id로** 지정하세요 (`wP:p3`처럼 워크스페이스가 접두사).

## `--reharness` 가 팬을 일부만 잡는다

팀 프리셋의 역할명과 **팬 라벨이 정확히 일치**해야 매칭됩니다.
운영 중 추가된 역할은 프리셋에 없어도 공통 규칙을 받지만, **에이전트로 감지되지 않는 팬(빈 셸)은 건너뜁니다.**

```bash
orch --reharness --dry-run   # 누가 잡히는지 먼저 확인
```

## 프롬프트의 "최근 산출물" 목록이 비어 있다

작업 디렉토리에 `.md`·`.html`·`.json`·`.csv`·`.svg` 파일이 없거나, `--cwd`가 잘못 지정된 경우입니다.

```bash
orch --reharness --dry-run
# 출력의 "작업 디렉토리:" 를 확인
```

## Linux에서 표 정렬이 깨진다

`column` 구현 차이입니다(util-linux vs BSD). 기능에는 영향이 없고 `orch --status` 표시만 어긋납니다.
직접 보려면:

```bash
herdr agent list | jq -r '.result.agents[] | select(.workspace_id=="wX")
  | "\(.agent_status) \(.name // "-") \(.pane_id)"'
```

## WSL에서 스크립트가 `\r` 오류를 낸다

CRLF 줄바꿈입니다.

```bash
git config --global core.autocrlf input
# 이미 받았다면
sed -i 's/\r$//' ~/.local/bin/orch ~/.local/bin/orch-msg
```

## 비용이 예상보다 많이 나온다

에이전트 수를 줄이세요. 멀티에이전트는 일반 채팅 대비 **약 15배** 토큰을 씁니다(Anthropic 공식 자료).

- 놀고 있는 에이전트는 닫습니다 (`herdr pane close <pane>`)
- 순차 의존 작업은 나눠도 이득이 없습니다
- 판단이 단순한 역할은 `--model sonnet` 으로 낮춥니다

---

여기 없는 문제는 [이슈](../../issues)로 알려주세요. **재현 절차와 `herdr --version` · OS**를 함께 적어주시면 빠릅니다.

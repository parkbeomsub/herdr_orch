# 권한 설정

에이전트가 `herdr` 명령을 쓸 때마다 승인을 물으면 오케스트레이션이 멈춥니다.
`~/.claude/settings.json` 의 `permissions.allow` 에 아래를 넣으세요.
`install.sh` 가 물어볼 때 `y` 하면 자동으로 들어갑니다.

```json
{
  "permissions": {
    "allow": [
      "Bash(herdr agent list)",
      "Bash(herdr agent get:*)",
      "Bash(herdr agent read:*)",
      "Bash(herdr agent send:*)",
      "Bash(herdr agent wait:*)",
      "Bash(herdr agent rename:*)",
      "Bash(herdr agent focus:*)",
      "Bash(herdr pane list:*)",
      "Bash(herdr pane get:*)",
      "Bash(herdr pane read:*)",
      "Bash(herdr pane layout:*)",
      "Bash(herdr pane rename:*)",
      "Bash(herdr pane focus:*)",
      "Bash(herdr pane zoom:*)",
      "Bash(herdr pane split:*)",
      "Bash(herdr pane send-text:*)",
      "Bash(herdr pane send-keys:*)",
      "Bash(herdr tab list:*)",
      "Bash(herdr tab create:*)",
      "Bash(herdr tab rename:*)",
      "Bash(herdr workspace list)",
      "Bash(herdr wait:*)",
      "Bash(herdr notification show:*)",
      "Bash(orch-msg:*)",
      "Bash(orch --status:*)",
      "Bash(orch --list-teams)"
    ]
  }
}
```

## 일부러 뺀 것

| 제외 | 이유 |
|---|---|
| `herdr pane run` | `pane run <팬> "<아무 명령>"` 으로 **Bash 권한 검사를 우회**해 임의 코드 실행이 됩니다. 허용하면 샌드박스가 무의미해집니다 |
| `herdr pane close` | 파괴적 — 진행 중인 작업이 사라집니다 |
| `herdr workspace close` | 파괴적 |
| `herdr agent start` | 프로세스를 띄웁니다 |

결과적으로 orch가 **새 에이전트를 띄우거나 팬을 닫을 때만** 승인을 묻습니다.
불편해 보이지만 이게 유일하게 남은 안전장치입니다 — 전부 열면 에이전트가 임의 코드를
아무 팬에서나 실행할 수 있습니다.

## 프로젝트 단위로만 허용하려면

`~/.claude/settings.json`(전역) 대신 프로젝트의 `.claude/settings.local.json` 에 넣으세요.
단 **그 디렉토리에서 실행할 때만** 적용되므로, 다른 경로에서 `orch`를 돌리면 다시 물어봅니다.

#!/usr/bin/env python3
"""herdr 전체 상태 스냅샷 / 복원 계획 생성기.

사용법:
    orch-snapshot            # 스냅샷 생성 (재부팅 전 실행)
    orch-snapshot --list     # 저장된 스냅샷 목록
    orch-snapshot --show     # 최신 스냅샷 요약 출력

스냅샷 위치: ~/.config/herdr/snapshots/<타임스탬프>/
  session.json       herdr 레이아웃 원본 백업
  state.json         workspace/tab/pane/agent 조회 결과 통합
  RESTORE.md         사람이 읽는 복원 대장 (역할 ↔ claude 세션 ID)
  restore.sh         재부팅 후 실행할 복원 스크립트
"""
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERDR_CFG = Path.home() / ".config" / "herdr"
SNAP_ROOT = HERDR_CFG / "snapshots"
CLAUDE_PROJECTS = Path.home() / ".claude" / "projects"


def herdr_json(*args):
    """herdr CLI를 JSON 모드로 호출. 실패하면 None."""
    try:
        out = subprocess.run(
            ["herdr", *args], capture_output=True, text=True, timeout=30
        )
        if out.returncode != 0:
            return None
        return json.loads(out.stdout)
    except Exception:
        return None


def cwd_slug(cwd):
    """claude가 프로젝트 디렉토리를 파일명으로 바꾸는 규칙(경로의 / 를 - 로)."""
    return cwd.replace("/", "-")


def transcript_path(cwd, session_id):
    """해당 세션의 대화 기록 jsonl 경로. 실제 존재 여부까지 확인한다.

    cwd 기준 경로에 없으면 projects 전체를 훑는다. 팬이 뜬 디렉토리와
    claude 가 기록을 남긴 디렉토리가 어긋나는 경우가 있기 때문.
    """
    if not session_id:
        return None, False
    if cwd:
        p = CLAUDE_PROJECTS / cwd_slug(cwd) / f"{session_id}.jsonl"
        if p.exists():
            return str(p), True
    for found in CLAUDE_PROJECTS.glob(f"*/{session_id}.jsonl"):
        return str(found), True
    return str(CLAUDE_PROJECTS / cwd_slug(cwd or "")/ f"{session_id}.jsonl"), False


def collect():
    """살아있는 herdr 서버에서 현재 상태를 통째로 긁어온다."""
    state = {
        "captured_at": datetime.now().isoformat(timespec="seconds"),
        "workspaces": [],
        "tabs": [],
        "panes": [],
        "agents": [],
    }
    ws = herdr_json("workspace", "list")
    if ws is None:
        return None
    state["workspaces"] = ws["result"].get("workspaces", [])
    tb = herdr_json("tab", "list")
    state["tabs"] = tb["result"].get("tabs", []) if tb else []
    pn = herdr_json("pane", "list")
    state["panes"] = pn["result"].get("panes", []) if pn else []
    ag = herdr_json("agent", "list")
    state["agents"] = ag["result"].get("agents", []) if ag else []
    return state


def build_plan(state, session_doc):
    """워크스페이스 → 탭 → 팬 순서로 복원 대장을 조립한다.

    session.json(레이아웃 원본)과 라이브 조회 결과를 합쳐,
    팬 하나당 {역할명, cwd, 세션ID, 기록파일 존재여부}를 확정한다.
    """
    live_by_pane = {p["pane_id"]: p for p in state["panes"]}
    ws_label = {w["workspace_id"]: w.get("label") or "" for w in state["workspaces"]}

    plan = []
    for w in session_doc.get("workspaces", []):
        wid = w.get("id")
        entry = {
            "workspace_id": wid,
            "label": w.get("custom_name") or ws_label.get(wid, ""),
            "identity_cwd": w.get("identity_cwd"),
            "active_tab": w.get("active_tab"),
            "tabs": [],
        }
        for ti, t in enumerate(w.get("tabs", [])):
            tab = {
                "index": ti,
                "custom_name": t.get("custom_name"),
                "layout": t.get("layout"),
                "focused": t.get("focused"),
                "root_pane": t.get("root_pane"),
                "panes": [],
            }
            for local_num, p in sorted(
                t.get("panes", {}).items(), key=lambda kv: int(kv[0])
            ):
                sess = (p.get("agent_session") or {}).get("value")
                cwd = p.get("cwd")
                tpath, exists = transcript_path(cwd, sess)
                pane_id = f"{wid}:p{local_num}"
                live = live_by_pane.get(pane_id, {})
                tab["panes"].append(
                    {
                        "local_num": int(local_num),
                        "pane_id_guess": pane_id,
                        "label": p.get("label") or live.get("label") or "",
                        "cwd": cwd,
                        "session_id": sess,
                        "transcript": tpath,
                        "transcript_exists": exists,
                        "title": live.get("terminal_title_stripped", ""),
                    }
                )
            entry["tabs"].append(tab)
        plan.append(entry)
    return plan


def write_restore_md(snap_dir, plan, state):
    """재부팅 후 눈으로 보고 복구할 수 있는 대장 문서."""
    lines = [
        "# herdr 복원 대장",
        "",
        f"- 스냅샷 시각: {state['captured_at']}",
        f"- 워크스페이스 {len(plan)}개 / 에이전트 {len(state['agents'])}개",
        "",
        "## 재부팅 후 절차",
        "",
        "1. `herdr` 실행 → 레이아웃이 자동 복원되는지 먼저 확인",
        "2. 팬은 살아났는데 claude가 비어 있으면, 각 팬에서 아래 표의",
        "   `claude --resume <세션ID>` 를 실행 (cwd 맞춘 뒤)",
        "3. 레이아웃까지 날아갔으면 `restore.sh` 실행",
        "",
    ]
    total = 0
    missing = 0
    for w in plan:
        lines.append(f"## {w['workspace_id']} — {w['label']}")
        lines.append("")
        lines.append(f"기준 디렉토리: `{w.get('identity_cwd') or '-'}`")
        lines.append("")
        for t in w["tabs"]:
            name = t["custom_name"] or f"탭 {t['index'] + 1}"
            lines.append(f"### {name}")
            lines.append("")
            lines.append("| 팬 | 역할 | cwd | 복원 명령 | 기록 |")
            lines.append("|---|---|---|---|---|")
            for p in t["panes"]:
                total += 1
                if p["session_id"] and p["transcript_exists"]:
                    cmd = f"`claude --resume {p['session_id']}`"
                    mark = "O"
                elif p["session_id"]:
                    cmd = f"`claude --resume {p['session_id']}`"
                    mark = "기록없음"
                    missing += 1
                else:
                    cmd = "`claude`"
                    mark = "-"
                    missing += 1
                label = p["label"] or p["title"] or "-"
                lines.append(
                    f"| {p['local_num']} | {label} | `{p['cwd'] or '-'}` | {cmd} | {mark} |"
                )
            lines.append("")
    lines.insert(
        5, f"- 복원 가능 팬: {total - missing}/{total} (기록 파일 확인 완료)"
    )
    (snap_dir / "RESTORE.md").write_text("\n".join(lines), encoding="utf-8")
    return total, missing


def write_restore_sh(snap_dir, plan):
    """레이아웃까지 날아간 최악의 경우에 쓰는 재구성 스크립트.

    herdr가 session.json을 복원해주면 이 스크립트는 필요 없다.
    워크스페이스/탭/팬을 다시 만들고 각 팬에 --resume 을 꽂는다.
    """
    sh = [
        "#!/usr/bin/env bash",
        "# herdr 레이아웃 + claude 세션 복원 스크립트",
        "# 주의: herdr가 이미 레이아웃을 복원했다면 실행하지 말 것(중복 생성됨).",
        "set -uo pipefail",
        "",
        'if ! herdr status >/dev/null 2>&1; then',
        '  echo "herdr 서버가 떠 있지 않습니다. 먼저 herdr 를 실행하세요." >&2',
        "  exit 1",
        "fi",
        "",
        "resume_pane() {",
        "  local pane=\"$1\" dir=\"$2\" sess=\"$3\" label=\"$4\"",
        '  herdr pane rename "$pane" "$label" >/dev/null 2>&1',
        '  if [ -n "$sess" ]; then',
        '    herdr pane send-text "$pane" "cd $dir && claude --resume $sess"',
        "  else",
        '    herdr pane send-text "$pane" "cd $dir && claude"',
        "  fi",
        '  herdr pane send-keys "$pane" enter',
        "}",
        "",
        'echo "== 복원 시작 =="',
    ]
    for w in plan:
        sh.append(f'echo "-- {w["workspace_id"]} {w["label"]} --"')
        for t in w["tabs"]:
            for p in t["panes"]:
                sess = p["session_id"] or ""
                label = (p["label"] or "").replace('"', "'")
                sh.append(
                    f'# {w["workspace_id"]} / {t["custom_name"] or t["index"] + 1} / {label}'
                )
                sh.append(
                    f'# resume_pane "<pane_id>" "{p["cwd"]}" "{sess}" "{label}"'
                )
    sh += [
        "",
        'echo "== 위 주석의 pane_id 를 실제 값으로 채운 뒤 사용하세요 =="',
        'echo "대부분의 경우 herdr 가 레이아웃을 자동 복원하므로 RESTORE.md 만으로 충분합니다."',
    ]
    path = snap_dir / "restore.sh"
    path.write_text("\n".join(sh), encoding="utf-8")
    path.chmod(0o755)


def do_snapshot():
    state = collect()
    if state is None:
        print("herdr 서버에 연결할 수 없습니다. herdr 가 실행 중인지 확인하세요.", file=sys.stderr)
        return 1

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    snap_dir = SNAP_ROOT / stamp
    snap_dir.mkdir(parents=True, exist_ok=True)

    src = HERDR_CFG / "session.json"
    session_doc = {}
    if src.exists():
        shutil.copy2(src, snap_dir / "session.json")
        session_doc = json.loads(src.read_text(encoding="utf-8"))

    (snap_dir / "state.json").write_text(
        json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    plan = build_plan(state, session_doc)
    (snap_dir / "plan.json").write_text(
        json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    total, missing = write_restore_md(snap_dir, plan, state)
    write_restore_sh(snap_dir, plan)

    # 최신 스냅샷을 가리키는 심볼릭 링크
    latest = SNAP_ROOT / "latest"
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(snap_dir)

    print(f"스냅샷 저장 완료: {snap_dir}")
    print(f"  워크스페이스 {len(plan)}개, 팬 {total}개, 복원 가능 {total - missing}개")
    print(f"  대장 문서: {snap_dir / 'RESTORE.md'}")
    print(f"  최신 링크: {latest}")
    return 0


def do_list():
    if not SNAP_ROOT.exists():
        print("스냅샷이 없습니다.")
        return 0
    for d in sorted(SNAP_ROOT.iterdir()):
        if d.is_dir() and not d.is_symlink():
            plan_file = d / "plan.json"
            n = 0
            if plan_file.exists():
                plan = json.loads(plan_file.read_text(encoding="utf-8"))
                n = sum(len(t["panes"]) for w in plan for t in w["tabs"])
            print(f"{d.name}  워크스페이스/팬 {n}개  {d}")
    return 0


def do_show():
    latest = SNAP_ROOT / "latest"
    if not latest.exists():
        print("스냅샷이 없습니다. 먼저 orch-snapshot 을 실행하세요.")
        return 1
    print((latest / "RESTORE.md").read_text(encoding="utf-8"))
    return 0


def do_verify():
    """재부팅 후 실제 복원 결과를 직전 스냅샷과 대조한다.

    세션 ID 단위로 비교해야 의미가 있다. 팬 ID는 재할당될 수 있지만
    claude 세션 ID는 대화 그 자체를 가리키기 때문.
    """
    latest = SNAP_ROOT / "latest"
    if not latest.exists():
        print("비교할 스냅샷이 없습니다.", file=sys.stderr)
        return 1
    plan = json.loads((latest / "plan.json").read_text(encoding="utf-8"))
    expected = {}
    for w in plan:
        for t in w["tabs"]:
            for p in t["panes"]:
                if p["session_id"]:
                    expected[p["session_id"]] = (
                        w["label"] or w["workspace_id"],
                        p["label"] or p["title"] or "-",
                    )

    state = collect()
    if state is None:
        print("herdr 서버에 연결할 수 없습니다.", file=sys.stderr)
        return 1
    actual = {
        (a.get("agent_session") or {}).get("value")
        for a in state["agents"]
    }
    actual.discard(None)

    restored = [s for s in expected if s in actual]
    lost = [s for s in expected if s not in actual]

    print(f"스냅샷 기준 claude 세션 {len(expected)}개")
    print(f"  복원됨   {len(restored)}개")
    print(f"  미복원   {len(lost)}개")
    if lost:
        print("\n미복원 목록 (해당 팬에서 아래 명령으로 수동 복구):")
        for s in lost:
            ws, label = expected[s]
            print(f"  [{ws}] {label}")
            print(f"    claude --resume {s}")
    return 0


def do_shutdown():
    """재부팅 직전 안전 종료: 스냅샷을 먼저 뜨고 herdr 서버를 정상 종료한다.

    정상 종료를 거쳐야 session.json 이 마지막 상태로 확정 저장된다.
    강제 전원 차단은 마지막 자동 저장 이후 변경분을 잃는다.
    """
    rc = do_snapshot()
    if rc != 0:
        return rc
    print("\nherdr 서버를 정상 종료합니다...")
    out = subprocess.run(
        ["herdr", "server", "stop"], capture_output=True, text=True, timeout=60
    )
    print(out.stdout.strip() or out.stderr.strip())
    print("\n이제 재부팅해도 안전합니다. 재부팅 후: herdr → orch-snapshot --verify")
    return 0


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--list":
        sys.exit(do_list())
    if arg == "--show":
        sys.exit(do_show())
    if arg == "--verify":
        sys.exit(do_verify())
    if arg == "--shutdown":
        sys.exit(do_shutdown())
    sys.exit(do_snapshot())

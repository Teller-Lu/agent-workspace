# -*- coding: utf-8 -*-
# extract_day.py <YYYY-MM-DD> <outfile> [workspace_root]
# 抽取指定本地日期的 Codex 对话摘要（用户原话 + 助手要点），供每周工作总结自动化(step3)用。
#
# transcript 定位：~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
#   每个 rollout 文件首行 session_meta.payload.cwd 标记该会话的工作目录。
#   三级定位：环境 CODEX_SESSIONS_DIR 覆盖 > ~/.codex/sessions（默认）> 扫不到则写空摘要。
# 工作区匹配：session_meta.payload.cwd 或 turn_context.payload.cwd 与传入 workspace_root 标准化后比较。
# 抽取：文件级 mtime 粗筛 + 内部 timestamp 精定当天；按 response_item.payload.type=message 的
#   role 区分 user（input_text）/ assistant（output_text），滤 developer 角色与噪声注入。
# 时区：用系统本地时区（与 git / 文件变更记录 的本地日期一致），不写死某地偏移。
# 找不到 transcript（未用 Codex / 路径不匹配）→ 写空摘要，worklog 端据此不编造对话内容。
import json, os, re, sys, glob
from datetime import datetime, timedelta


def norm_path(p):
    """标准化路径用于比较：统一分隔符、小写、去尾部分隔符、normpath"""
    if not p:
        return ""
    p = p.replace("/", os.sep).replace("\\", os.sep).rstrip("\\/")
    return os.path.normpath(p).lower()


def find_sessions_dir():
    """定位 Codex sessions 目录"""
    env = os.environ.get("CODEX_SESSIONS_DIR")
    if env and os.path.isdir(env):
        return env
    base = os.path.expanduser("~/.codex/sessions")
    return base if os.path.isdir(base) else None


def session_cwd(rollout_path):
    """读 rollout 文件前几行，取 session_meta/turn_context 的 cwd；无则 None"""
    try:
        with open(rollout_path, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i > 20:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("type") in ("session_meta", "turn_context"):
                    cwd = (o.get("payload") or {}).get("cwd", "")
                    return cwd or None
    except Exception:
        pass
    return None


def local_date(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d")
    except Exception:
        return None


def text_of(content, want_types):
    """从 content 数组提取指定类型块的文本"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") in want_types)
    return ""


NOISE = (
    "# AGENTS.md instructions",
    "<permissions instructions>",
    "<system",
    "<command",
    "<bash-input",
    "<bash-stdout",
    "<local-command",
    "Caveat:",
    "<system-reminder",
    "[Request interrupted",
    "<user-",
    "Base directory for this skill:",
    "<function_results>",
    "This session is being continued",
    "<local-command-std",
    "Result of calling the",
)


def is_noise(m):
    s = m.lstrip()
    return any(s.startswith(p) for p in NOISE) or len(s.strip()) < 5


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("用法: extract_day.py <YYYY-MM-DD> <outfile> [workspace_root]\n")
        sys.exit(2)
    target = sys.argv[1]
    outfile = sys.argv[2]
    wsroot = sys.argv[3] if len(sys.argv) > 3 else \
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    wsroot = os.path.abspath(wsroot)
    target_cwd = norm_path(wsroot)

    sessions = find_sessions_dir()
    if not sessions:
        with open(outfile, "w", encoding="utf-8") as w:
            w.write(f"# {target} 对话摘要\n\n"
                    "（未找到 Codex 对话记录目录；仅凭文件变更生成，勿编造对话内容）\n")
        print(f"{target}: sessions-dir 未找到（wsroot={wsroot}）-> {outfile}")
        return

    td = datetime.strptime(target, "%Y-%m-%d").date()
    lo = td - timedelta(days=1)

    def in_window(f):
        try:
            return datetime.fromtimestamp(os.path.getmtime(f)).date() >= lo
        except Exception:
            return False

    all_rollouts = glob.glob(os.path.join(sessions, "**", "*.jsonl"), recursive=True)
    matched = [f for f in all_rollouts
               if in_window(f) and norm_path(session_cwd(f) or "") == target_cwd]

    users, assts = [], []
    for f in matched:
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    if o.get("type") != "response_item":
                        continue
                    p = o.get("payload") or {}
                    if p.get("type") != "message":
                        continue
                    ts = o.get("timestamp")
                    if not ts or local_date(ts) != target:
                        continue
                    role = p.get("role", "")
                    content = p.get("content", [])
                    if role == "user":
                        txt = text_of(content, ("input_text", "text")).strip()
                        if txt and not is_noise(txt):
                            users.append(txt[:1500])
                    elif role == "assistant":
                        txt = text_of(content, ("output_text", "text")).strip()
                        if txt:
                            assts.append(txt[:200])
        except Exception as e:
            sys.stderr.write(f"skip {os.path.basename(f)}: {e}\n")

    with open(outfile, "w", encoding="utf-8") as w:
        w.write(f"# {target} 对话摘要（本地时区）\n\n")
        w.write(f"## 用户原话（{len(users)} 条）\n\n")
        for i, m in enumerate(users, 1):
            w.write(f"[U{i}] {m}\n\n")
        w.write(f"## 助手回复要点（{len(assts)} 条·各截前200字）\n\n")
        for i, m in enumerate(assts, 1):
            w.write(f"[A{i}] {m}\n")
    print(f"{target}: user={len(users)} asst={len(assts)} -> {outfile}")


if __name__ == "__main__":
    main()
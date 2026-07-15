# -*- coding: utf-8 -*-
# extract_day.py <YYYY-MM-DD> <outfile> [workspace_root]
# 抽取指定本地日期的 Claude 对话摘要（用户原话 + 助手要点），供每周工作总结自动化(step3)用。
#
# transcript 定位：~/.claude/projects/<工作区路径编码>/*.jsonl
#   编码 = 启动 cwd 的绝对路径按 [^A-Za-z0-9] → '-'（Claude Code 的项目目录命名规则）。
#   先定位根 project 目录（环境 CLAUDE_PROJECTS_DIR 覆盖 > 由工作区根推导 > 扫 projects 目录按末段匹配），
#   再通配 <根名> 与 <根名>-* 纳入根 cwd + 所有子目录 cwd 会话——子目录（如某子项目）作为独立
#   cwd 启动的会话存在各自 project 目录（名以 <根编码>- 为前缀），不一并扫会漏采其当天工作。
# 抽取：mtime 窗口粗筛 + 内部时间戳精定当天，uuid 去重，滤噪声（工具结果/命令/skill 注入）。
# 时区：用系统本地时区（与 git / 文件变更记录 的本地日期一致），不写死某地偏移。
# 找不到 transcript（未用 Claude Code / 路径不匹配）→ 写空摘要，worklog 端据此不编造对话内容。
import json, os, re, sys, glob
from datetime import datetime, timedelta


def encode_path(p):
    return re.sub(r'[^A-Za-z0-9]', '-', p)


def gitbash_to_win(p):
    # /c/Users/me/proj -> C:\Users\me\proj（Git Bash 形式还原为 Windows 盘符形式再编码）
    m = re.match(r'^/([a-zA-Z])/(.*)$', p)
    return (m.group(1).upper() + ':\\' + m.group(2).replace('/', '\\')) if m else None


def find_projects_dirs(wsroot):
    """返回该工作区的所有 Claude project 目录：根 cwd + 所有子目录 cwd 会话。
    Claude Code 按 cwd 分目录存 transcript；子目录 cwd 的目录名 = <根编码>-<子路径编码>，
    必以 <根编码> 为前缀。故先定位根目录名，再通配 <根名> 与 <根名>-* 纳入全部子目录会话。
    （原只返回根目录一个 → 漏采所有子目录独立 cwd 会话的工作，本次修复。）"""
    env = os.environ.get("CLAUDE_PROJECTS_DIR")
    if env and os.path.isdir(env):
        return [env]   # 显式指定单目录，尊重不通配
    base = os.path.expanduser("~/.claude/projects")
    if not os.path.isdir(base):
        return []
    # 1) 定位"根 project 目录名"：精确编码匹配
    root_name = None
    cands = [encode_path(wsroot)]
    win = gitbash_to_win(wsroot)
    if win:
        cands.append(encode_path(win))
    for c in cands:
        if os.path.isdir(os.path.join(base, c)):
            root_name = c
            break
    # 2) fallback：目录名以工作区末段结尾（如 -Agent-Claude），唯一命中才用
    if not root_name:
        tail = encode_path(os.path.basename(wsroot.rstrip('/\\')))
        hits = [d for d in os.listdir(base)
                if d.endswith(tail) and os.path.isdir(os.path.join(base, d))]
        if len(hits) == 1:
            root_name = hits[0]
    if not root_name:
        return []
    # 3) 根 <根名> 自身 + 所有子目录 cwd <根名>-*（子目录 cwd 会话）
    dirs = []
    root_path = os.path.join(base, root_name)
    if os.path.isdir(root_path):
        dirs.append(root_path)
    dirs += sorted(d for d in glob.glob(os.path.join(base, root_name + "-*"))
                   if os.path.isdir(d))
    return dirs


def local_date(ts):
    try:
        # 对话 timestamp 为 UTC（带 Z）；转系统本地时区取日期
        return datetime.fromisoformat(ts.replace('Z', '+00:00')).astimezone().strftime('%Y-%m-%d')
    except Exception:
        return None


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get('text', '') for b in content
                         if isinstance(b, dict) and b.get('type') == 'text')
    return ""


def has_toolresult(content):
    return isinstance(content, list) and any(
        isinstance(b, dict) and b.get('type') == 'tool_result' for b in content)


NOISE = ('<command-name>', '<local-command', '<bash-input', '<bash-stdout', 'Caveat:',
         '<system-reminder', '[Request interrupted', '<user-', '<command-message', '<command-args',
         'Base directory for this skill:', 'Result of calling the', '<function_results>',
         'This session is being continued', '<local-command-std')


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

    projects_dirs = find_projects_dirs(wsroot)
    if not projects_dirs:
        with open(outfile, 'w', encoding='utf-8') as w:
            w.write(f"# {target} 对话摘要\n\n"
                    "（未找到 Claude 对话记录目录；仅凭文件变更生成，勿编造对话内容）\n")
        print(f"{target}: projects-dir 未找到（wsroot={wsroot}）-> {outfile}")
        return

    td = datetime.strptime(target, "%Y-%m-%d").date()
    # 只设下限：mtime 早于目标日的文件不可能含当天消息；晚于的必须扫（续聊/压缩会把当天消息重包进后存的文件）
    lo = td - timedelta(days=1)

    def in_window(f):
        try:
            return datetime.fromtimestamp(os.path.getmtime(f)).date() >= lo
        except Exception:
            return False

    seen, users, assts = set(), [], []
    # 跨"根 + 各子目录 cwd"多个 project 目录合并；uuid 去重（seen）天然防跨目录/续聊重复
    files = [g for d in projects_dirs for g in glob.glob(os.path.join(d, "*.jsonl"))]
    for f in (x for x in files if in_window(x)):
        try:
            with open(f, encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    if o.get('type') not in ('user', 'assistant'):
                        continue
                    u = o.get('uuid')
                    if u in seen:
                        continue
                    seen.add(u)
                    ts = o.get('timestamp')
                    if not ts or local_date(ts) != target:
                        continue
                    t = o.get('type')
                    content = (o.get('message') or {}).get('content')
                    if t == 'user':
                        if has_toolresult(content):
                            continue
                        txt = text_of(content).strip()
                        if txt and not is_noise(txt):
                            users.append(txt[:1500])
                    else:
                        txt = text_of(content).strip()
                        if txt:
                            assts.append(txt[:200])
        except Exception as e:
            sys.stderr.write(f"skip {os.path.basename(f)}: {e}\n")

    with open(outfile, 'w', encoding='utf-8') as w:
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

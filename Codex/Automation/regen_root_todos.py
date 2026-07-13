#!/usr/bin/env python3
# regen_root_todos.py — 根级「项目待办」聚合重建（确定性，不依赖 LLM）
# 扫描工作区各子项目的 待办.md「## 待办总表」+「## 已完成」两张标准表，
# 只重写根级 待办.md 内「## 项目待办」到文件末尾这一节，绝不触碰上方「## 手记待办」。
# 用法: python3 regen_root_todos.py [--dry-run]
import os, sys, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
WSROOT = os.path.dirname(HERE)
ROOT_TODO = os.path.join(WSROOT, "待办.md")
SECTION = "## 项目待办"

def find_project_todos():
    """一层子目录下的 待办.md（排除根级自身）。"""
    out = []
    for name in os.listdir(WSROOT):
        sub = os.path.join(WSROOT, name)
        if not os.path.isdir(sub) or name.startswith("."):
            continue
        todo = os.path.join(sub, "待办.md")
        if os.path.isfile(todo):
            out.append((name, todo))
    return out

def parse_table(lines, start_idx):
    """从 start_idx 找下一个 markdown 表格，返回 (header, rows, next_idx)。"""
    i = start_idx
    # 跳到第一行 | （表头）
    while i < len(lines) and "|" not in lines[i]:
        i += 1
    if i >= len(lines):
        return [], [], i
    header = [c.strip() for c in lines[i].strip().strip("|").split("|")]
    i += 1
    # 分隔行 |---|---|
    if i < len(lines) and re.match(r"^\s*\|?[\s:\-|]+\|?\s*$", lines[i]):
        i += 1
    rows = []
    while i < len(lines):
        ln = lines[i]
        if "|" not in ln or not ln.strip():
            break
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        rows.append(cells)
        i += 1
    return header, rows, i

def parse_todo_file(path):
    """返回 (todo_rows, done_rows)。todo_rows 含未完成；done_rows 含已完成。"""
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    todo_rows, done_rows = [], []
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.strip().startswith("## 待办总表"):
            _, todo_rows, i = parse_table(lines, i + 1)
        elif ln.strip().startswith("## 已完成"):
            _, done_rows, i = parse_table(lines, i + 1)
        else:
            i += 1
    return todo_rows, done_rows

def build_section(projects):
    """projects: [(name, path, todo_rows, done_rows)]"""
    out = []
    out.append(SECTION)
    out.append("")
    out.append("<!-- 本节由 Automation/regen_root_todos.py 自动重建，请勿手工编辑。 -->")
    out.append("<!-- 各项目权威来源：各项目目录下的 待办.md（标准表：待办总表 / 已完成） -->")
    out.append("")
    # 未完成：按优先级 P0-P3 分组
    all_unfin = []  # (pri, name, row)
    for name, path, todo_rows, done_rows in projects:
        for row in todo_rows:
            if len(row) < 6:
                continue
            # 状态列（标准模板第 6 列索引5）含"已完成"则跳过
            status = row[5] if len(row) > 5 else ""
            if "完成" in status or "[x]" in status.lower():
                continue
            pri = (row[3] if len(row) > 3 else "").strip() or "P3"
            all_unfin.append((pri, name, row))
    if all_unfin:
        out.append("### 未完成（按优先级）")
        out.append("")
        for pri in ["P0", "P1", "P2", "P3"]:
            grp = [x for x in all_unfin if x[0].upper() == pri]
            if not grp:
                continue
            out.append("**%s**" % pri)
            out.append("")
            out.append("| 项目 | 编号 | 短标题 | 优先级 | 限期 | 状态 | 跳转 |")
            out.append("|---|---|---|---|---|---|---|")
            for _, name, row in grp:
                no = row[0]; title = row[1] if len(row) > 1 else ""
                lim = row[4] if len(row) > 4 else ""; st = row[5] if len(row) > 5 else ""
                out.append("| %s | %s | %s | %s | %s | %s | [%s](%s/待办.md) |" % (
                    name, no, title, pri, lim, st, no, name))
            out.append("")
    else:
        out.append("（暂无未完成的项目待办。）")
        out.append("")
    # 已完成：按项目分组，组内按完成日倒序
    any_done = any(done_rows for _, _, _, done_rows in projects)
    if any_done:
        out.append("### 已完成（按项目，组内完成日倒序）")
        out.append("")
        for name, path, todo_rows, done_rows in projects:
            if not done_rows:
                continue
            # 完成日是最后一列
            done_sorted = sorted(done_rows, key=lambda r: (r[-1] if len(r) > 5 else ""), reverse=True)
            out.append("**%s**" % name)
            out.append("")
            out.append("| 编号 | 短标题 | 优先级 | 登记日 | 完成日 |")
            out.append("|---|---|---|---|---|")
            for row in done_sorted:
                no = row[0]; title = row[1] if len(row) > 1 else ""
                pri = row[3] if len(row) > 3 else ""
                reg = row[4] if len(row) > 4 else ""; fin = row[5] if len(row) > 5 else ""
                out.append("| %s | %s | %s | %s | %s |" % (no, title, pri, reg, fin))
            out.append("")
    # 中转：当天完成的正式待办，供 daily_worklog.sh 读取
    digests = os.path.join(HERE, ".digests")
    os.makedirs(digests, exist_ok=True)
    today_done = []
    import datetime
    today = os.environ.get("TODAY") or datetime.date.today().isoformat()
    for name, path, todo_rows, done_rows in projects:
        for row in done_rows:
            fin = row[-1] if len(row) > 5 else ""
            if fin == today:
                today_done.append("%s: %s" % (name, row[1] if len(row) > 1 else row[0]))
    with open(os.path.join(digests, "today_done.txt"), "w", encoding="utf-8") as f:
        f.write("TODAY=%s\n" % today)
        f.write("\n".join(today_done))
    return "\n".join(out) + "\n"

def main():
    dry = "--dry-run" in sys.argv
    projects_raw = find_project_todos()
    projects = []
    for name, path in projects_raw:
        t, d = parse_todo_file(path)
        projects.append((name, path, t, d))
    new_section = build_section(projects)
    with open(ROOT_TODO, encoding="utf-8") as f:
        content = f.read()
    idx = content.find("\n" + SECTION)
    if idx == -1:
        # 没有 ## 项目待办 节，追加
        head = content.rstrip() + "\n\n"
        merged = head + new_section
    else:
        head = content[:idx+1]  # 保留到 \n 之后
        merged = head + new_section
    if dry:
        sys.stdout.write(new_section)
        return
    with open(ROOT_TODO, "w", encoding="utf-8") as f:
        f.write(merged)
    print("[regen_root_todos] 已重建「## 项目待办」，项目数=%d" % len(projects))

if __name__ == "__main__":
    main()
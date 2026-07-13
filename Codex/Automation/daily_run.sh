#!/usr/bin/env bash
# daily_run.sh — 每日自动化编排器（任务计划程序调用本脚本）
# 执行顺序：① 文件变更记录(daily_changelog.sh) → ② 待办聚合(regen_root_todos.py) → ③ 工作总结(daily_worklog.sh)
# 任一步失败不阻断后续（文件变更记录与待办聚合是确定性的，工作总结依赖无头 codex）。
set -u
export SCRIPT_NAME="run"
source "$(dirname "$0")/_common.sh"
cd "$WSROOT" || { err "无法进入 $WSROOT"; exit 1; }

info "==== daily_run 开始 $TODAY ===="
bash "$AUTODIR/daily_changelog.sh" || warn "daily_changelog 非零退出"
python3 "$AUTODIR/regen_root_todos.py" || warn "regen_root_todos 非零退出"
# regen 之后若改了 待办.md，先提交
if git rev-parse HEAD >/dev/null 2>&1; then
  git add 待办.md 2>/dev/null
  git diff --cached --name-only | grep -q . && git commit -m "[AUTO] 待办聚合 更新 $TODAY" >/dev/null 2>&1
fi
bash "$AUTODIR/daily_worklog.sh" || warn "daily_worklog 非零退出"
info "==== daily_run 完成 $TODAY ===="
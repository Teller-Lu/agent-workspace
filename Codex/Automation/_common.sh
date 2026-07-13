#!/usr/bin/env bash
# ============================================================
# _common.sh — Automation 共用容错层（daily_run/daily_changelog/daily_worklog 共 source）
# 提供：工作区根自动检测、日志、代理预检+退避重试、无头 codex 调用+连接类失败重试。
# ------------------------------------------------------------
# 设计取自"确定性的活交 shell/python、无头 codex 只做读摘要→写文件"：
#   step1 文件变更记录、step2 待办聚合 都是确定性的，不用 codex；
#   只有 step3 每周工作总结 需要无头 codex 读当天对话摘要来综合判断。
# 无头 codex 走本地代理连 API 时，代理离线会 ConnectionRefused 且易被脚本吞成静默漏更——
# 故调 codex 前预检代理端口、退避重试；整段离线则跳过、记日志，交次日回看补齐（不为离线死等）。
# ------------------------------------------------------------
# 配置（automation.conf，从 automation.conf.example 复制；已 gitignore）：
#   CODEX_BIN        无头 codex 可执行（默认走 PATH 的 `codex`）
#   PROXY_HOST/PORT  仅当 codex 需经本地代理联网且代理可能离线时填；PORT 留空=直连不探代理
# 可环境覆盖（测试）：TODAY、PROXY_WAITS（退避秒序列）、CODEX_RETRY_WAIT
# ============================================================
set -u

# 工作区根 = Automation 目录的上一级（脚本位置决定，与 cwd 无关）
AUTODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSROOT="$(cd "$AUTODIR/.." && pwd)"

# 读配置（可选；不存在则用默认）
CONF="$AUTODIR/automation.conf"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
CODEX_BIN="${CODEX_BIN:-codex}"
PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${PROXY_PORT:-}"
PROXY_WAITS="${PROXY_WAITS:-30 60}"
CODEX_RETRY_WAIT="${CODEX_RETRY_WAIT:-60}"

# 今天（可环境覆盖，用于补跑某天）
TODAY="${TODAY:-$(date +%Y-%m-%d)}"

LOG="$AUTODIR/daily_${SCRIPT_NAME:-common}.log"
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null || true; }
info() { echo "[info] $*"; log "info $*"; }
warn() { echo "[warn] $*" >&2; log "WARN $*"; }
err()  { echo "[err]  $*" >&2; log "ERR  $*"; }

# 探一次代理端口是否可连（bash 内建 /dev/tcp）。未配置 PROXY_PORT 视为无需代理 → 通。
probe_proxy() {
  [ -z "$PROXY_PORT" ] && return 0
  (exec 3<>"/dev/tcp/$PROXY_HOST/$PROXY_PORT") 2>/dev/null
}

# 退避等代理就绪：首探 + PROXY_WAITS 退避重试。未配置代理直接通。通返回 0；始终不通返回 1。
wait_proxy() {
  [ -z "$PROXY_PORT" ] && return 0
  probe_proxy && return 0
  local w i=1
  for w in $PROXY_WAITS; do
    log "代理($PROXY_HOST:$PROXY_PORT)未就绪，等 ${w}s 后第 $i 次重试…"
    sleep "$w"
    if probe_proxy; then log "代理已就绪（第 $i 次重试）"; return 0; fi
    i=$((i+1))
  done
  log "代理探测 $i 次仍不通（$PROXY_HOST:$PROXY_PORT），判定离线"
  return 1
}

# 调无头 codex；连接类失败隔 CODEX_RETRY_WAIT 秒再试一次（共 2 次）。
# 用法：out=$(call_codex "$PROMPT"); rc=$?  —— stdout=codex 最后一条消息；rc=0 成功。
# 非交互 exec 模式：workspace-write 沙箱 + never 审批 + --ephemeral（不持久化本次会话，
#   避免污染 transcript 抽取）+ --skip-git-repo-check（工作区未 init git 时也能跑）
#   + -C 指定工作根 + -o 捕获最后消息到临时文件。
# prompt 经 stdin 传入（避免命令行长度限制）；rc=0 也校验输出无连接错关键词（治假成功）。
call_codex() {
  local prompt="$1" out rc try=1 lastmsg
  lastmsg="$(mktemp)"
  while :; do
    printf '%s' "$prompt" | "$CODEX_BIN" exec \
      -s workspace-write \
      -c approval_policy=never \
      --skip-git-repo-check \
      --ephemeral \
      -C "$WSROOT" \
      -o "$lastmsg" \
      2>>"$LOG"
    rc=$?
    out=""
    [ -f "$lastmsg" ] && out=$(cat "$lastmsg" 2>/dev/null)
    if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -qiE 'unable to connect|connection ?refused|network|timed? ?out'; then
      printf '%s' "$out"; rm -f "$lastmsg"; return 0
    fi
    log "codex 第 $try 次失败(rc=$rc)：$out"
    [ "$try" -ge 2 ] && { printf '%s' "$out"; rm -f "$lastmsg"; return 1; }
    log "隔 ${CODEX_RETRY_WAIT}s 重试 codex…"; sleep "$CODEX_RETRY_WAIT"
    try=$((try+1))
  done
}
#!/usr/bin/env bash
# ============================================================
# daily_worklog.sh — 每日自动起草"每周工作总结"（工作内容, step3）
# 由 daily_run.sh 编排调用（也可独立跑）。设计：确定性抽数 + 无头 claude 只格式化补写。
#   周一–周五：抽当天对话摘要 + 读当天文件变更记录行 → 无头 claude 写 简洁+详细 两档 → 只补缺失行
#   周六       ：不跑（周末并入周日）
#   周日       ：兜底补齐本周缺失的工作日行 + 写"周末"行（周六+周日合并）
# 铁律 write-if-missing：只补该文件本周"缺失"的天行，绝不覆盖已存在行（护人工精修/手写历史）。
# 分工：extract_day.py 抽对话摘要（确定性）；无头 claude 只格式化 + 用 Write 补写（不给 Bash）。
#
# 用法：
#   bash daily_worklog.sh                          # 正式（按今天）
#   TODAY=2026-01-15 bash daily_worklog.sh         # 模拟某天（测试）
#   TERSE=/tmp/a.md DETAIL=/tmp/b.md TODAY=... bash daily_worklog.sh   # 写副本（测试，不碰真文件）
# 失败仅记日志（daily_worklog.log），不弹窗。缺失天由次日回看补齐。
# ============================================================
set -u
export SCRIPT_NAME="worklog"
source "$(dirname "$0")/_common.sh"

CHANGELOG="${CHANGELOG:-$WSROOT/文件变更记录.md}"
TERSE="${TERSE:-$WSROOT/WorkRecord/每周工作总结.md}"
DETAIL="${DETAIL:-$WSROOT/WorkRecord/每周工作总结-详细.md}"
DRYRUN="${1:-}"

cd "$WSROOT" || { err "cd $WSROOT 失败"; exit 1; }

DOW=$(date -d "$TODAY" '+%u' 2>/dev/null || date '+%u')
WEEKNAMES=("" "周一" "周二" "周三" "周四" "周五" "周六" "周日")
log "=== start TODAY=$TODAY dow=$DOW dryrun='$DRYRUN' terse=$TERSE detail=$DETAIL ==="

[ "$DOW" = "6" ] && { log "周六不跑，退出"; log "=== end ==="; exit 0; }

DIGDIR="$AUTODIR/.digests"
mkdir -p "$DIGDIR"

# 读 regen_root_todos.py 产出的"今天完成的正式待办"中转站（仅当其 TODAY 与本次一致才用，防读到别天旧数据）
RELAY="$DIGDIR/today_done.txt"
DONELIST="（无：今天没有从项目待办完成表检出完成项）"
if [ -f "$RELAY" ] && head -n1 "$RELAY" | grep -q "TODAY=$TODAY"; then
  BODY=$(tail -n +2 "$RELAY")
  [ -n "$BODY" ] && DONELIST="$BODY"
fi
log "今日完成正式待办：$(printf '%s' "$DONELIST" | tr '\n' ';')"

# 抽某天对话摘要（确定性 python），回显文件路径
digest(){ python "$AUTODIR/extract_day.py" "$1" "$DIGDIR/day_$1.txt" "$WSROOT" >>"$LOG" 2>&1 || log "extract_day $1 出错"; echo "$DIGDIR/day_$1.txt"; }
# 文件变更记录去掉 <!-- --> 注释块后的正文（避免抓到注释里的示例行）
CONTENT=$(awk '/<!--/{c=1} c!=1{print} /-->/{c=0}' "$CHANGELOG" 2>/dev/null)
# 取某天（YYYY-MM-DD）那行的正文（蒸馏版 changelog 行格式：- 周X（日期）：内容）
chgline(){ printf '%s\n' "$CONTENT" | grep -m1 "（$1）" | sed 's/^[^：]*：//' || true; }
# 本周标题（文件变更记录最上面那条含"第N周"的标题；两档沿用同一周次）
WEEKHDR=$(printf '%s\n' "$CONTENT" | grep -m1 '第.*周' || echo "")
log "本周标题=$WEEKHDR"
# 本周周次 key（如"第 38 周"），用于在两档里定位本周小节、判断某天是否已写
WKKEY=$(printf '%s' "$WEEKHDR" | grep -oE '第[ ]*[0-9]+[ ]*周' | head -1)
# 某文件"最上面的本周小节"（含 WKKEY 的标题行 到 下一个标题行之前）；无本周小节则空
week_sec(){ awk -v k="$WKKEY" '/^#/{ if(inwk) exit; if(k!="" && index($0,k)) inwk=1 } inwk{ print }' "$1" 2>/dev/null; }
# 某文件本周小节里是否已有某天行（$2 如"周一"/"周末"）；已有返回 0。WKKEY 空视为缺失
day_present(){ [ -n "$WKKEY" ] && week_sec "$1" | grep -q "$2："; }

COMMON_RULES=$(cat <<EOF
【两档格式】
A) 简洁档文件：$TERSE
   每天一行： - 周X：<1~2 句，周报口径，这天我做了什么>
B) 详细档文件：$DETAIL
   每天一行： * 周X：<尽量全：文件层面的事 + 对话里体现的讨论/竞品核实/方案定名/汇报准备/机制研究/学习等>
两档周标题都沿用文件变更记录的本周周次（与下方"本周标题"一致；两档各自本周小节不存在就新建、插在文件最上面、最新周在上）。

【铁律】
1. **只补缺失**：某文件本周小节里若已有 "周X：" 那一行，**整段跳过该天该文件、一个字都不许改**（那是人工或先前写的，终稿归人）。
2. 本周小节不存在就新建，只放周标题 + 需要补的那几行，别预填空白天。
3. 对话摘要里有开会/汇报/口头交代痕迹的要带上；纯线下、摘要里没有的**别编造**。
4. 不动其他周、其他天、注释。数据里"（无）/（无变更）"就照实写"（无）"。
5. "完成的正式待办"清单是已确认事实，有则必须写进当天工作内容；清单为"（无…）"就不提。
6. **文件变更兜底**：对照"文件变更（文件变更记录）"行，凡某项目/子目录当天有实质文件产出（新增或较多修改）却在对话摘要里找不到对应工作内容的，**必须据文件变更为该项目补写一句**（按文件名合理概括做了什么，不虚构细节）——对话摘要可能漏采子目录独立 cwd 启动的会话，而文件变更源自 git、覆盖全部会话，是防漏的兜底信号源。
本周标题（两档同一周次）：$WEEKHDR
EOF
)

if [ "$DOW" = "7" ]; then
  # ---------- 周日：① 回看补齐本周缺失的工作日行（周一~周五）② 写"周末"行 ----------
  WK_MON=$(date -d "$TODAY -6 days" '+%Y-%m-%d')
  D6=$(date -d "$TODAY -1 days" '+%Y-%m-%d')
  DATA_BLOCK=""; NEED_DAYS=()
  for off in 0 1 2 3 4; do
    dd=$(date -d "$WK_MON +$off days" '+%Y-%m-%d'); wn="${WEEKNAMES[$((off+1))]}"
    if ! day_present "$TERSE" "$wn" || ! day_present "$DETAIL" "$wn"; then
      dg=$(digest "$dd"); NEED_DAYS+=("$wn")
      DATA_BLOCK+="### $wn（$dd）（回看补缺）
- 对话摘要：用 Read 读 $dg
- 文件变更（文件变更记录）：$(chgline "$dd")

"
    fi
  done
  log "周日回看补工作日：${NEED_DAYS[*]:-（无缺失）}；另写周末行"
  G6=$(digest "$D6"); G7=$(digest "$TODAY")
  PROMPT=$(cat <<EOF
你在维护"每周工作总结"（工作内容日志，两档）。今天 $TODAY（周日）：① 回看补齐本周此前缺失的工作日行（下面列出的，若无则跳过该步）；② 写本周"周末"行（周六+周日合并）。按 write-if-missing：某文件本周已有的天/周末行就跳过不动。

${DATA_BLOCK}### 周末（$D6 周六 + $TODAY 周日）
- 周六对话摘要：用 Read 读 $G6
- 周日对话摘要：用 Read 读 $G7
- 周末文件变更（文件变更记录）：$(chgline "$D6")；$(chgline "$TODAY")
- 周末完成的正式待办：
$DONELIST

对两个文件：补上面列出的缺失工作日行（已有则跳过）+ 各写"周末"行（已有则跳过）。

$COMMON_RULES

完成后只回复：WORKLOG_DONE
EOF
)
else
  # ---------- 周一~周五：写当天行 + 回看补齐本周此前缺失的工作日 ----------
  WN="${WEEKNAMES[$DOW]}"
  WK_MON=$(date -d "$TODAY -$((DOW-1)) days" '+%Y-%m-%d')
  NEED_DATES=(); NEED_DAYS=()
  for off in $(seq 0 $((DOW-1))); do
    dd=$(date -d "$WK_MON +$off days" '+%Y-%m-%d'); wn="${WEEKNAMES[$((off+1))]}"
    if [ "$off" -eq "$((DOW-1))" ]; then
      NEED_DATES+=("$dd"); NEED_DAYS+=("$wn")                 # 今天：总要（upsert）
    elif ! day_present "$TERSE" "$wn" || ! day_present "$DETAIL" "$wn"; then
      NEED_DATES+=("$dd"); NEED_DAYS+=("$wn")                 # 此前某天在任一档缺失：回看补
    fi
  done
  log "本周需写/补：${NEED_DAYS[*]}"
  DATA_BLOCK=""
  for idx in "${!NEED_DATES[@]}"; do
    dd="${NEED_DATES[$idx]}"; wn="${NEED_DAYS[$idx]}"; dg=$(digest "$dd")
    if [ "$dd" = "$TODAY" ]; then
      DATA_BLOCK+="### $wn（$dd）（今天，必写）
- 对话摘要：用 Read 读 $dg
- 文件变更（文件变更记录）：$(chgline "$dd")
- 完成的正式待办：
$DONELIST

"
    else
      DATA_BLOCK+="### $wn（$dd）（回看补缺）
- 对话摘要：用 Read 读 $dg
- 文件变更（文件变更记录）：$(chgline "$dd")

"
    fi
  done
  PROMPT=$(cat <<EOF
你在维护"每周工作总结"（工作内容日志，两档）。今天 $TODAY（$WN）。下面列出本周需要写/补的工作日（标"今天"的必写；标"回看补缺"的是此前漏掉的），请按 write-if-missing 补进两个文件。

$DATA_BLOCK
逐天处理：某文件本周小节已有该天行就跳过不动；否则用该天"对话摘要 + 文件变更记录行(+完成待办)"起草该天工作内容写入。今天（$WN）两档都必须有。

$COMMON_RULES

完成后只回复：WORKLOG_DONE
EOF
)
fi

if wait_proxy; then
  log "代理就绪（或无需代理），调用无头 claude 写工作总结…"
  CL_OUT=$(call_claude "$PROMPT"); CL_RC=$?
  log "claude 结果 rc=$CL_RC 输出=${CL_OUT}"
else
  log "代理离线，跳过写工作总结（缺失天由次日回看补齐）"
fi

# 幂等兜底提交（无头 claude 的 Write 通常已由 PostToolUse hook 自动 commit；这里再兜一次，无改动则跳过）
if [ "$DRYRUN" != "--dry-run" ] && git rev-parse HEAD >/dev/null 2>&1; then
  git add "$TERSE" "$DETAIL" 2>/dev/null
  if git diff --cached --name-only | grep -q .; then
    git commit -m "[AUTO] 工作总结 更新 $TODAY" >/dev/null 2>&1 && log "已 commit 工作总结"
  fi
fi
log "=== end ==="

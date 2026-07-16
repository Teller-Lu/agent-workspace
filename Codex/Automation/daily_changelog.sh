#!/usr/bin/env bash
# daily_changelog.sh — 每日文件变更记录（确定性，不依赖 LLM）
#   - 周一~五：把当天 git 净文件变更写成一行，upsert 到当周小节，并回看补齐本周缺失工作日
#   - 周六：不跑（周末并入周日）
#   - 周日：① 兜底补齐本周缺失工作日行 ② 写"周末"行 ③ git commit（推送由用户自行决定）
# 由 Windows 任务计划程序每天 22:00 触发，或手动：TODAY=YYYY-MM-DD bash daily_changelog.sh
set -u
export SCRIPT_NAME="changelog"
source "$(dirname "$0")/_common.sh"

CL="$WSROOT/文件变更记录.md"
DIGESTS="$AUTODIR/.digests"
mkdir -p "$DIGESTS"

# ISO 周编号 + 周一日期（GNU date）
iso_week() { date -d "$1" +%V 2>/dev/null || date -j -f %Y-%m-%d "$1" +%V 2>/dev/null; }
week_monday() {
  # 输入 YYYY-MM-DD，输出该周周一的 YYYY-MM-DD
  local dow; dow=$(date -d "$1" +%u 2>/dev/null || date -j -f %Y-%m-%d "$1" +%u 2>/dev/null)
  date -d "$1 - $((dow-1)) days" +%Y-%m-%d 2>/dev/null || date -j -v-$((dow-1))d -f %Y-%m-%d "$1" +%Y-%m-%d 2>/dev/null
}
weekday_cn() { case $1 in 1) echo 一;; 2) echo 二;; 3) echo 三;; 4) echo 四;; 5) echo 五;; 6) echo 六;; 7) echo 日;; esac; }

# 某天的 git 净变更文件清单（去重、去空、按顶级目录归组的摘要）
day_changes() {
  local d="$1"
  local files
  files=$(cd "$WSROOT" && git log --since="$d 00:00:00" --until="$d 23:59:59" --name-only --pretty=format: 2>/dev/null \
        | grep -vE '^\s*$' | sort -u)
  local n; n=$(echo "$files" | grep -c . 2>/dev/null) || n=0
  if [ "$n" -eq 0 ]; then echo "无提交"; return; fi
  local dirs; dirs=$(echo "$files" | sed 's#/.*##' | sort -u | sed ':a; N; $!ba; s/\n/、/g')
  echo "改动 $n 个文件，涉及：${dirs}"
}

# 在 文件变更记录.md 里查找某天是否已有行
has_day() { grep -q "（$1）" "$CL" 2>/dev/null; }

# 写某天的一行（若不存在）
write_day() {
  local d="$1" dow cn summary
  dow=$(date -d "$d" +%u 2>/dev/null || date -j -f %Y-%m-%d "$d" +%u 2>/dev/null)
  cn=$(weekday_cn "$dow")
  if has_day "$d"; then return; fi
  summary=$(day_changes "$d")
  # 确保当周小节存在
  local wk mon sun
  wk=$(iso_week "$d"); mon=$(week_monday "$d")
  sun=$(date -d "$mon +6 days" +%Y-%m-%d 2>/dev/null || date -j -v+6d -f %Y-%m-%d "$mon" +%Y-%m-%d 2>/dev/null)
  if ! grep -q "第 ${wk} 周" "$CL" 2>/dev/null; then
    # 找最后一个 ### 日标题 或 文件末尾前插入周标题；简单做法：追加
    {
      echo ""
      echo "## 第 ${wk} 周（${mon} 至 ${sun}）"
    } >> "$CL"
  fi
  echo "- 周${cn}（${d}）：${summary}" >> "$CL"
  log "写入 周${cn}（${d}）：${summary}"
}

cd "$WSROOT" || { err "无法进入 $WSROOT"; exit 1; }

dow_today=$(date -d "$TODAY" +%u 2>/dev/null || date -j -f %Y-%m-%d "$TODAY" +%u 2>/dev/null)

# 回看补齐本周此前缺失的工作日（周一~五）
mon=$(week_monday "$TODAY")
for i in 1 2 3 4 5; do
  d=$(date -d "$mon +$((i-1)) days" +%Y-%m-%d 2>/dev/null || date -j -v+$((i-1))d -f %Y-%m-%d "$mon" +%Y-%m-%d 2>/dev/null)
  # 只补今天及之前
  if [ "$d" \< "$TODAY" ] || [ "$d" = "$TODAY" ]; then
    write_day "$d"
  fi
done

if [ "$dow_today" = "6" ]; then
  info "周六，跳过（并入周日）。"
  exit 0
fi

if [ "$dow_today" = "7" ]; then
  # 周日：写"周末"行
  if ! grep -q "周末（${TODAY}" "$CL" 2>/dev/null; then
    sat=$(date -d "$TODAY -1 days" +%Y-%m-%d 2>/dev/null || date -j -v-1d -f %Y-%m-%d "$TODAY" +%Y-%m-%d 2>/dev/null)
    summary=$(day_changes "$sat"; echo "---"; day_changes "$TODAY")
    echo "- 周末（${sat}~${TODAY}）：${summary}" >> "$CL"
    log "写入周末行"
  fi
fi

# 提交（有变更才提交）
if git rev-parse HEAD >/dev/null 2>&1; then
  git add 文件变更记录.md 2>/dev/null
  if git diff --cached --name-only | grep -q .; then
    git commit -m "[AUTO] 文件变更记录 更新 $TODAY" >/dev/null 2>&1 && info "已 commit 文件变更记录"
  fi
fi
info "daily_changelog 完成"
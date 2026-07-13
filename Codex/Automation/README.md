# Automation — 每日自动化

工作区每日自动化脚本，由 Windows 任务计划程序每天 22:00 触发 `daily_run.sh` 编排执行。

## 执行链（daily_run.sh）

```
① daily_changelog.sh   → 文件变更记录.md（当天 git 净文件变更，纯 shell 确定性，不用模型）
② regen_root_todos.py  → 待办.md「项目待办」节（各项目待办聚合，确定性，不用模型）
③ daily_worklog.sh     → WorkRecord/每周工作总结.md + 每周工作总结-详细.md（无头 codex 分析当天对话）
```

任一步失败不阻断后续。①② 确定性、无模型也照常；③ 无 codex 配置或代理离线时跳过并记日志，次日回看补齐。

## 产物

| 产物 | 位置 | 生成者 | 引擎 |
|---|---|---|---|
| 文件变更记录 | `../文件变更记录.md` | daily_changelog.sh | git + shell（确定性） |
| 待办聚合 | `../待办.md`（仅「## 项目待办」节） | regen_root_todos.py | shell（确定性） |
| 简洁周报 | `../WorkRecord/每周工作总结.md` | daily_worklog.sh | 无头 codex |
| 详细述职 | `../WorkRecord/每周工作总结-详细.md` | daily_worklog.sh | 无头 codex |

## 两步分工（为什么这么分）

- **文件变更记录（step1）纯 shell**：`git log/diff` 取当天净变更，确定性、零依赖、可复现——不需要模型也能跑，最健壮。
- **每周工作总结（step3）无头 codex**：光看文件变更看不出"为什么做、讨论了什么、方案怎么定、汇报怎么准备"——这些只在当天对话里。故用无头 codex 读"当天对话摘要 + 文件变更行"综合起草。
  - 确定性的活交给脚本：`extract_day.py` 按日期从 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 抽当天对话摘要（匹配 `session_meta.payload.cwd` 等于工作区根）；
  - 无头 codex 只负责"读摘要 → 用 Write 补写两档"（`codex exec -s workspace-write -c approval_policy=never --ephemeral`），完事回哨兵 `WORKLOG_DONE`。

## 配置（仅 step3 工作总结需要）

```bash
cp automation.conf.example automation.conf   # 按需编辑；已 gitignore
```

- `CODEX_BIN`：无头 codex 可执行，默认走 PATH 的 `codex`；未加入 PATH 就填绝对/相对路径。
- `PROXY_PORT`：仅当 codex 联网需经本地代理且代理可能离线时填（如 7890）；留空=直连、不探代理。
- **认证**：`codex exec` 复用 `codex login` 的登录态（`~/.codex/auth.json`）；使用公司模型时，`~/.codex/config.toml` 配 `model_provider`/`model`/`base_url` 即可。**首次使用前务必先在终端跑一次 `codex login`（或配好 config.toml），否则无头调用会因无认证而失败。**
- **零配置即可跑**：codex 在 PATH、已登录、无需代理时，本文件可不创建。

## 每日节奏

| 日 | ①文件变更记录 | ②待办聚合 | ③工作总结 |
|---|---|---|---|
| 周一~五 | 写当天 + 回看补缺 | 重建 | 写当天 + 回看补缺 |
| 周六 | 跳过（并入周日） | 重建 | 跳过 |
| 周日 | 兜底补全周 + 写周末行 | 重建 | 兜底补全周 + 写周末行 |

## 容错与漏跑自愈

- **代理离线不静默漏更**（若配了 `PROXY_PORT`）：调 codex 前预检代理端口 + 退避重试；整段离线则跳过、记日志、不误改文件。
- **write-if-missing**（工作总结）：只补本周缺失的天行，绝不覆盖已存在行（护人工精修/手写历史）。
- **漏跑自愈**：某天漏跑，次日起每日回看自动补齐缺失工作日（精算缺失天，避免超时）。手动补：

```bash
TODAY=2026-01-15 bash Automation/daily_run.sh
```

## 与真实 Codex 工作区的关系

本套从一套已跑通的 Codex 工作区自动化蒸馏而来，机制一致（无头 codex 读当天对话起草工作总结）。为发布做的两点通用化：
- 路径 / codex 可执行 / 代理端口全部参数化（`automation.conf` + 工作区根自动检测 + transcript 目录自动定位），不绑定特定机器；
- 文件变更记录这步蒸馏版用纯 shell 确定性罗列（真实版用无头 codex 按项目细化归组）——蒸馏版取"零依赖、可复现"优先。

## 手动操作

```bash
# 只跑某一步
bash Automation/daily_changelog.sh
python Automation/regen_root_todos.py            # --dry-run 预览
bash Automation/daily_worklog.sh

# 查询审计
powershell -File 安全审核.ps1 -Last 10
```
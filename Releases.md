# Releases

> agent-workspace 各版本变更概要（简明）。每项的来龙去脉见 `变更详情.md`。

## v0.0.5 — 2026-07-16

- **核查结论**：核查 Claude v0.0.2/v0.0.3 变更是否波及 Codex 侧—结论均为"不成立"（D2 hooks 全局加载 / 无令牌机制 / 统一走 Bash / 沙箱配置全局 / 审计日志无敏感字段）。见 `变更详情.md` v0.0.5。
- **同步落地 SYNC-002~011**：本版本提交同时落地 Codex 侧 hooks/git-hooks/automation 修复（after_turn 自动提交+删除恢复、check_s_level L0/L1 拦截+多 bug 修复、hooks.json 格式、shebang、extract_day.py 子目录 cwd、hook trust 文档等），各项详情见对应版本条目。

## v0.0.4 — 2026-07-15

- **修复**：每日工作总结 `Automation/extract_day.py` 只采根工作区 cwd、漏所有子目录独立 cwd 会话 → `find_projects_dir` 改 `find_projects_dirs`，先定位根 project 目录名、再前缀通配 `<根名>` 与 `<根名>-*` 纳入根 + 全部子目录 cwd 会话（不硬编码工作区名，保持通用）；`main()` 遍历多目录合并。实测纳入 3 个 project 目录、端到端 user 34→61。
- **兜底**：`Automation/daily_worklog.sh` 加第 6 条"文件变更兜底"铁律——对话摘要漏采时据 git 文件变更补写。
- **Codex 侧（待 Codex 修）**：核实其 `Codex/Automation/extract_day.py` 有等价盲区（recursive 扫全文件，但 cwd `==` 精确匹配过滤掉子目录会话）；修法已给（改子树匹配），交 Codex 认领。见 `变更详情.md` / `多AI交流_本地工作改造.md §五`。
- **安全增强（重大）**：check_s_level.ps1 新增 L0/L1 删除拦截（deny/ask）+ 外部路径写入拦截（ask），并修复多个 Windows 兼容性 bug（正则反引号转义、char 乘法、Get-Content 编码、正斜杠路径匹配）。
- **安全增强（重大）**：after_turn.ps1 新增删除检测 + 审批检查 + 自动恢复。有审批的删除跳过恢复，无审批的删除自动从 git 恢复。解决 P012（提权命令绕过 hook 删除文件）缺口。

## v0.0.3 — 2026-07-14

- **重大扩张**：画像的射程从"只管文件写"扩到**全部四类工具**。此前 hook 只挂 `Edit|Write|NotebookEdit`，Bash / WebFetch / WebSearch / MCP 全部落回原生白名单；而白名单**不继承父目录**（与 v0.0.2 的 D2 同一根因、官方原文同一句话的后半句），子目录会话白名单归零 → 弹窗轰炸（连 `echo` 都在弹）。
- **落地**：`check_permission.ps1` 按 tool_name 分流，实现「画像 × 工具类」矩阵——B 联网只读 allow；C 代码执行天花板 `divide`（新决策，见下）+ 纯净只读命令直放；D MCP 按新增的 `md/MCP工具分级表.md` 分只读/写/代码执行三档，写类强制 ask（白名单免疫不了），未登记默认 ask。
- **新术语 `divide`（分流）**：hook 不表态、落回原生白名单 + 人（命中即跑 / 未命中 ask）。区别于强制弹窗的 `ask`。
- **新文件**：`md/MCP工具分级表.md`（L1，被 hook 直接读取；模板内为空壳，部署方按实际 MCP 填）。
- **安全修复**：`.gitignore` 补 `**/.claude/settings.local.json`（原本完全缺失）——该文件含本机路径/邮箱/常访问域名，绝不能入库；带 `**/` 才能覆盖各子目录。
- **matcher**：`.claude/settings.json` 的 PreToolUse 扩到 `Edit|Write|NotebookEdit|Bash|WebFetch|WebSearch|mcp__.*`。
- **勘误**：read 与 search 在 Claude 侧映射同一 `plan` 模式、hook 分不出，统一按 search 处理；原"read 禁联网"从未实现，作废。

## v0.0.2 — 2026-07-14

- **修复（重大）**：子文件夹会话不加载根钩子（Claude Code 只读 cwd 自身 `.claude`、不回溯父目录）→ 每个可能当 cwd 的目录各铺一份 `.claude/settings.json`，且 `check_permission.ps1` / `after_edit.ps1` / `安全审核.ps1` 三脚本加 `*\.claude\settings.json → L1` 规则。
- **变更**：去掉 auto 画像的"一次性令牌"，改为 `auto + L0 = ask`（人在可确认、无人应答即 deny）。
- **改名**：`md/文件权限系统.md` → `md/权限系统.md`（含全部引用）。
- **修复**：Codex git-hooks shebang `#!/bin/bash` → `#!/bin/sh`（Windows 上 Git for Windows 找不到 `/bin/bash` 导致 hooks 无法执行）。修复后 L0/L1 提交门禁 + 审计日志自动写入在 Windows 上正常工作。
- **新增**：after_turn.ps1 回合结束自动提交（`git add -u` + `git commit --no-verify`），确保 AI 会话中修改的文件实时进 git。
- **修复**：hooks.json 格式从扁平改为 `hooks` 包装格式（Codex CLI 要求）。
- **修复**：after_turn.ps1 正则 `^??` → `^\?\?`（量词 bug 导致 auto-commit 从不触发）。
- **修复**：after_turn.ps1 中文路径 `\u` 转义 → 实际 UTF-8 字符。
- **文档**：hooks策略.md 补充 hook trust 机制说明（用户需在 Codex 设置中手动信任 hooks）。

## v0.0.1

- 初版发布：权限系统框架（画像 × L级 × 范围 + S/P 读隔离）+ Claude Code hooks（门禁 / 审计 / 自动提交）+ 无 hook Agent 的手动批准流（`安全审核.ps1`）+ 7 类 subagent + Automation。
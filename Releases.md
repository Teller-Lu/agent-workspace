# Releases

> agent-workspace 各版本变更概要（简明）。每项的来龙去脉见 `变更详情.md`。

## v0.0.2 — 2026-07-14

- **修复（重大）**：子文件夹会话不加载根钩子（Claude Code 只读 cwd 自身 `.claude`、不回溯父目录）→ 每个可能当 cwd 的目录各铺一份 `.claude/settings.json`，且 `check_permission.ps1` / `after_edit.ps1` / `安全审核.ps1` 三脚本加 `*\.claude\settings.json → L1` 规则。
- **变更**：去掉 auto 画像的"一次性令牌"，改为 `auto + L0 = ask`（人在可确认、无人应答即 deny）。
- **改名**：`md/文件权限系统.md` → `md/权限系统.md`（含全部引用）。

## v0.0.1

- 初版发布：权限系统框架（画像 × L级 × 范围 + S/P 读隔离）+ Claude Code hooks（门禁 / 审计 / 自动提交）+ 无 hook Agent 的手动批准流（`安全审核.ps1`）+ 7 类 subagent + Automation。

# S 级清单

> 本工作区中标记为 S（秘密）级的文件/目录。
> **拥有方 AI 可读写；其他方 AI 不可读**（hook 自动 deny，无需人工批准）。
> S 级路径同时列入各自工作区 `.gitignore`（保证不提交）。
> **gitignore ≠ S 清单**：gitignore 还含日志/临时等非 S 项，两者分开维护、保持同步。

## 规则

1. S 级文件/目录留在各自项目工作区内，不搬去单独 S 目录。
2. 新增 S 级标记时，同步更新本清单（下方 paths 代码块）和 `.gitignore`。
3. S 级文件不得放入会被自动加载的位置（CLAUDE.md / AGENTS.md / memory / SessionStart 注入路径）。
4. hook 脚本（`hooks/check_s_level.ps1`）从下方 ```paths 代码块读取路径，拦截 Bash 和 Read 工具的访问。

## 对方 AI 的 S 级路径（本 AI 不可读）

hook 脚本从下方代码块读取路径，每行一个，相对工作区根目录。`#` 开头为注释。

```paths
# 示例（取消注释并替换为实际对方 AI 的 S 级路径）：
# Codex 工作区填写 Claude 的 S 级路径（相对 Codex/ 根目录）：
# ../Claude/confidential/
#
# Claude 工作区填写 Codex 的 S 级路径（相对 Claude/ 根目录）：
# ../Codex/confidential/
```

## 本工作区自己的 S 级路径（需同步到 .gitignore）

以下路径是本工作区自己的 S 级文件/目录，需要同时列入 `.gitignore`：

```gitignore
# 示例（取消注释并替换为实际路径）：
# confidential/
```

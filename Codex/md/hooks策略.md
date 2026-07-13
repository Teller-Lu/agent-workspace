# Codex Hooks 策略

> Codex 支持原生 hooks（`.codex/hooks.json` + `[features].codex_hooks = true`），
> 但 PreToolUse/PostToolUse **仅匹配 shell 命令（Bash）**，不匹配文件编辑工具（Edit/Write/Read）。
> 文件编辑的权限检查和自动审计需要替代方案。

## 三层 hook 体系

| 层 | 覆盖范围 | 机制 | 配置位置 |
|---|---|---|---|
| **Codex 原生 hooks** | shell 命令 | PreToolUse/PostToolUse on Bash | `.codex/hooks.json` |
| **git hooks** | 提交前/后 | pre-commit/post-commit | `.git/hooks/` |
| **手动审核流** | 文件修改（L0/L1） | 安全审核.ps1 -Request/-Approve/-Log | 工作区内 |

## 1. Codex 原生 hooks（.codex/hooks.json）

### 支持的事件

| 事件 | 说明 | Codex 限制 |
|---|---|---|
| PreToolUse | 工具调用前 | **仅匹配 Bash**，不拦截 Edit/Write/Read |
| PostToolUse | 工具调用后 | **仅匹配 Bash**；文件编辑的 fixup 应改用 Stop hook |
| UserPromptSubmit | 用户提交 prompt | 支持，但忽略 matcher |
| SessionStart | 会话开始 | 匹配 startup 和 resume |
| Stop | 回合结束 | 可请求 continuation prompt，但忽略 matcher |

### hooks.json 模板

见同目录 `hooks.json.模板`。启用方式：在 `config.toml` 中添加 `[features]` 段设 `codex_hooks = true`。

## 2. git hooks（替代 Claude 的 PostToolUse）

Claude 用 PostToolUse 在每次文件编辑后自动审计+提交。Codex 的 PostToolUse 只匹配 Bash，
所以文件编辑后的审计改用 git hooks：

### pre-commit
- 检查暂存区是否有 L0/L1 文件未经 `安全审核.ps1 -Approve` 批准
- L0 变更 → **阻止提交**（exit 1）
- L1 变更 → **仅告警**（不阻止，提示用户确认）
- 见 `git-hooks/pre-commit`

### post-commit
- 提交完成后，自动追加审计日志到 `审计日志.jsonl`
- 记录 commit hash、文件、级别、时间戳
- 见 `git-hooks/post-commit`

### 差异说明
- Claude PreToolUse：**编辑前**拦截（文件没改就被挡）
- git pre-commit：**提交前**拦截（文件已改但还没进 git 历史）
- 搭配 Codex sandbox（防越界写）可补足，但不完全等价于"编辑前拦截"

## 3. 手动审核流（安全审核.ps1）

对于 L0/L1 文件的修改，使用 `安全审核.ps1` 的手动流：

```powershell
# 查询待审
.\安全审核.ps1 -Request -File "AGENTS.md" -Reason "更新 Codex 规则"
# 用户批准后
.\安全审核.ps1 -Approve -Id "ROOT-20260712-001"
# 修改完成后记录
.\安全审核.ps1 -Log -Id "ROOT-20260712-001" -File "AGENTS.md" -Action "Edit"
```

## 首次配置步骤

1. 复制 `md/config.toml.模板` 中的配置项到 `~/.codex/config.toml`（不复制 token/密钥）
2. 创建 `.codex/hooks.json`（参考 `md/hooks.json.模板`）
3. 在 `config.toml` 中设置 `[features] codex_hooks = true`
4. 复制 `git-hooks/pre-commit` 和 `git-hooks/post-commit` 到 `.git/hooks/`
5. 确保 `安全审核.ps1` 有执行权限
6. 初始化 git 仓库（如尚未）：`git init && git add -A && git commit -m "init"`
---

## S 级文件读取拦截

### 问题

Codex 的 PreToolUse/PostToolUse 仅匹配 Bash，不匹配 Read/Edit/Write。
Codex 读取文件通过 shell 命令（Get-Content 等），因此 Bash hook 可以拦截。

### 解法：check_s_level.ps1（PreToolUse on Bash）

`hooks/check_s_level.ps1`（UTF-8 BOM），配置在 `md/hooks.json.模板` 的 PreToolUse 段。

围栏必须使用标准 3 反引号（` ```paths `），否则正则匹配不到 S 级路径。自检机制：① paths 围栏存在但正则未匹配 → 写 WARNING 到 stderr；② paths 代码块匹配成功但 0 条路径提取 → 写 WARNING 到 stderr。
工作流程：
1. PreToolUse on Bash 触发 → 脚本读取 stdin 获取命令字符串
2. 从 `md/S级清单.md` 的 `` ```paths `` 代码块读取对方 AI 的 S 级路径
3. 归一化为绝对路径，生成正斜杠/反斜杠/双反斜杠三种变体
4. 检查命令字符串是否包含任何 S 级路径变体
5. 命中 → 返回 `permissionDecision: "deny"`（硬拦，无需人工）
6. 未命中 → exit 0（放行）

### Codex sandbox 不支持 denyRead

Codex sandbox 是 allow-list 模型（`:root` 全盘可读，无 deny 条目类型）。
config.toml 无 per-path 读禁配置。整个 .codex 目录搜索无 denyRead/deny_read/read_deny 匹配。

因此 Codex 侧 S 级保护方案：
1. **check_s_level.ps1**（PreToolUse on Bash）→ 拦截 shell 命令中的 S 级路径 ← 主要防线
2. **.gitignore** → S 级文件不提交（防泄露）← 兜底
3. **AGENTS.md 约定** → 不读对方 S 级目录 ← 约定补充

### 与 Claude 侧的对称缺口

| 维度 | Claude | Codex |
|---|---|---|
| Read 工具拦截 | PreToolUse 匹配 Read → deny ✅ | 无 Read 工具，靠 Bash hook |
| Bash 读拦截 | PreToolUse 匹配 Bash → check_s_level.ps1 ✅ | PreToolUse 匹配 Bash → check_s_level.ps1 ✅ |
| OS 级读禁 | sandbox.filesystem.denyRead（macOS/Linux） | 不支持 |
| 自动注入盲区 | CLAUDE.md/memory 拦不到 → 约定不放在自动加载位置 | 同 |

### 文件层强制不对称（必须知晓）

- **Claude PreToolUse**：**编辑前**拦截（deny → 文件没被改）
- **Codex git pre-commit**：**提交前**拦截（文件已改但进不了 git 历史）
- 二者不等价。Codex 侧搭配 sandbox（防越界写）补足，但不能 100% 等价"编辑前拦截"。

### ask 语义

- `deny` → 任何情况硬拦、无窗（绝对）
- `ask` → 交互会话会弹窗等人批；只有真正无头（无人无窗定时任务）才穿透
- 人工批准层在交互下可用

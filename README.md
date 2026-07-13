# agent-workspace

一个自带治理（权限 / 审计 / 待办 / hooks）与每日自动化总结的 AI Agent 文件系统框架。

---

## 这是什么项目？

agent-workspace 不是一个应用，而是一套**文件系统级的 AI 工作区治理框架**。它为 AI Agent 提供一个受控、可审计、有边界的工作环境——通过文件划定目标、建立规则、记录产出、追踪变更，让 AI 在多轮对话和长期项目中保持一致性和可追溯性。

框架从一个成熟的个人工作区蒸馏而来，剥离了所有项目内容，只保留可复用的治理框架与全部功能机制。任何人拿来即可用，所有功能已配置好。

---

## 为什么创建？

### 核心原因：AI 需要文件系统来弥补记忆与上下文的局限

AI Agent 无论多强大，都受限于两个根本约束：**上下文窗口有限**和**跨会话无持久记忆**。没有文件系统支撑时，AI 会面临：

- **目标漂移**：聊着聊着偏离了原始任务，无人拉回
- **规则遗忘**：上一轮约定的规范，下一轮对话全忘
- **进度断裂**：长期项目做到一半，新会话不知道前面做了什么
- **产出不可追溯**：改了哪些文件、为什么改、是否经过批准——全凭对话记录，无法审计
- **协作无序**：多个 AI 或人同时工作时，没有统一的权限和审计标准

**文件系统就是 AI 的外部大脑。** 它把目标、规则、进度、产出、审计全部固化为文件，让 AI 每次进入工作区都能快速恢复上下文、遵守既定规则、延续之前的工作。这不是"锦上添花"，而是让 AI 能够**正常且高效率地推进工作**的基础设施。

具体来说，这套文件系统提供：

| 解决的问题 | 文件系统的角色 |
|---|---|
| 目标不清 | 待办制度（项目级 + 根级聚合）划定任务目标与优先级 |
| 规则遗忘 | AGENTS.md / CLAUDE.md 固化 AI 必须遵守的规则 |
| 进度断裂 | 文件变更记录 + 工作记录持续追踪进展 |
| 产出不可追溯 | 审计日志（jsonl）+ 安全审核脚本记录每次变更 |
| 权限失控 | 三级变更权限（L0/L1/L2）+ 画像体系控制 AI 能做什么 |
| 跨 AI 隔离 | S/P 阅读等级实现文件级密级隔离 |
| 重复劳动 | 每日自动化生成变更记录、工作总结、待办聚合 |

### 其次：按需使用 AI 分管

框架支持 Codex 和 Claude Code **双 AI 分管**——各自有完整工作区，互不干扰。**没有此需求的用户，完全可以只使用其中一个工作区**（Codex/ 或 Claude/），根据自己的需求使用已经搭建好的功能。

### 功能来源

以下功能在设计过程中引入，解决实际痛点：

| 遇到的问题 | 解决方案 / 新增功能 |
|---|---|
| Codex"Approve for me"=放弃审批 | auto 画像（越界无人批=拦，而非无脑放行） |
| 跨 AI 文件泄露 | S/P 阅读等级 + check_s_level.ps1 硬拦 |
| Codex hooks 只匹配 Bash | git hooks（pre-commit/post-commit）补足文件编辑审计 |
| 手写工作总结费时 | Automation 每日自动总结（无头 CLI） |
| 待办散落各处 | 根级待办聚合脚本（regen_root_todos.py） |

---

## 具备哪些功能？

| 能力 | 说明 |
|---|---|
| **AI 分管体系** | Codex/ 和 Claude/ 各自完整工作区，互不干扰；Shared/ 跨 AI 协作；也可只用其中一个 |
| **权限系统** | 5 档画像（写范围/联网/审批）+ 三级变更权限（L0/L1/L2）+ S/P 阅读等级（跨 AI 密级隔离） |
| **修改即审计即提交** | 每次文件变更自动记录审计日志 + git commit |
| **6 类 subagent**（Claude） | requirement→design→develop→test + skills + git；Codex 无对应机制 |
| **待办制度** | 项目级标准模板（P0-P3）+ 根级全量聚合（脚本自动重建） |
| **变更标记规范** | 三色标记（🟡改 / 🟢增 / 🔴删）标注"最近一次改了啥" |
| **每日自动化** | 文件变更记录 / 工作总结（无头 CLI）/ 待办聚合，22:00 定时跑 |

### 1. AI 分管体系

Codex/ 和 Claude/ 各自是一个**完整、自洽的工作区**：有自己的 AI 手册（AGENTS.md / CLAUDE.md）、hooks、审计脚本、待办、项目目录、自动化。两个工作区互不干扰，各自独立 git 管理。

- **需要双 AI**：两个工作区同时使用，通过 Shared/ 协作，通过 S/P 等级隔离涉密文件
- **只需单 AI**：直接使用 Codex/ 或 Claude/ 其中一个，所有功能开箱即用
- 每个 AI 工作区都是独立可用的，不依赖另一个
- **跨 AI 协作**：`Shared/多AI交流.md` 记录跨 AI 的讨论与共识。规则：只追加不改写他人内容，用 `>> [Claude/Codex] 日期：` 前缀。只有"两个 AI 都要参与"的议题才记入此文件

### 2. 权限系统

权限系统由三个层次组成，分别控制 AI 的**对话级写权限**、**文件级变更权限**和**文件级阅读权限**：

#### 画像体系（对话级权限）

画像是 AI 对话级权限的抽象层，命名描述能力、不模仿原生名。5 个画像控制 AI 的写范围、联网和审批模式：

| 画像 | 含义 | Codex config | Claude 映射 |
|---|---|---|---|
| read | 离线只读 | read-only + never† | plan 模式 |
| search | 联网只读 | read-only + never† + network | plan 模式 + 联网 |
| work | 日常开发 | workspace-write + on-request | default + hook |
| auto | 无人值守 | workspace-write + on-request | acceptEdits + hook |
| bypass | 全放开 | danger-full-access + never | bypassPermissions |

> † `never` + `read-only`：Codex 回退到 "read-only + approvals disabled" = 真只读。

**为什么需要 auto 画像**：Codex UI 的"Approve for me"（替我审批）通过 `approvals_reviewer` 自动批准提权请求，本质是**放弃审批=无脑放行**。auto 画像不放弃审批，而是"越界无人批=拦"——这才是"无人值守但仍有边界"的正确实现。

work 与 auto 的 Codex config 相同（都是 on-request + workspace-write），区别在使用场景：work 有人在场应答审批请求，auto 无人应答→越界请求无人批→实际等于拦截。

详见各自工作区的 `md/画像映射表.md`。

#### 三级变更权限（L0 / L1 / L2）

变更权限控制的是 **AI 修改文件**时的审批要求。人类修改文件不受此限制（人类是权限的授予者）。

| 级别 | 含义 | AI 修改时的要求 |
|---|---|---|
| L0 | 权限制度、删除/移动/重命名等高风险操作 | 两次用户确认 + 审计 + 自动备份 + git tag |
| L1 | 关键指令文件（AGENTS.md / CLAUDE.md、hooks 配置等）、新增文件 | 用户批准 + 审计 |
| L2 | 普通说明、记录、工作文档 | 通常可直接修改 |

**执行机制（两家不同路径）**：

| Agent | 文件编辑拦截 | 自动审计 | 审批模式 |
|---|---|---|---|
| Claude | PreToolUse hook（Edit/Write，**编辑前**拦截） | PostToolUse hook（编辑后） | hook ask → 弹窗 |
| Codex | git pre-commit（**提交前**拦截）+ 安全审核.ps1 手动流 | git post-commit + Stop hook | sandbox approval（OS 级） |

> **注意**：Claude 在编辑前拦截（文件没改就被挡）；Codex 在提交前拦截（文件已改但进不了 git 历史）。二者不等价，Codex 侧搭配 sandbox 补足。

**Codex 手动审批流程**（改 L0/L1 文件）：

```text
① 安全审核.ps1 -Request -File "路径" [-Reason "原因"]   （L0 自动备份+打 tag）
② 用户：安全审核.ps1 -Approve -File "路径"
③ AI 修改文件
④ 安全审核.ps1 -Log -File "路径" -Summary "摘要"
```

**auto 画像下的令牌机制**：无人值守时 L0 无法交互双确认，用令牌替代——用户通过 `安全审核.ps1 -Approve` 预授权生成一次性令牌，git pre-commit 检查令牌有效性，commit 后消费。

#### S/P 阅读等级（文件级阅读权限）

控制 **AI 读取文件**的权限，与画像无关：

| 级别 | 含义 | 规则 |
|---|---|---|
| S（秘密） | 涉密材料 | 拥有方 AI 可读写（任何画像下）；其他方 AI 不可读（任何画像下，hook 硬拦 deny） |
| P（公开） | 一般文件 | 所有 AI 可读 |

- S 级文件**必须列入 `.gitignore`**（保证不入库）
- S 级文件**不得放入自动加载位置**（CLAUDE.md / AGENTS.md / memory / SessionStart 引用路径）——这是约定，因为自动注入的内容不是 Read/Bash 调用，hook 拦不到
- S 级路径在各自 `md/S级清单.md` 的 ` ```paths ` 代码块中维护
- `check_s_level.ps1` 从清单读取路径，拦截 Bash 和 Read 工具的访问，命中即 deny

### 3. 修改即审计即提交

每次文件变更都自动记录审计日志并提交到 git，无需手动维护：

- **Claude**：PreToolUse hook 拦截编辑 → PostToolUse hook 审计 + git commit（全自动）
- **Codex**：git pre-commit 检查权限 → git post-commit 写审计日志 + Stop hook 收尾
- 两种机制写同一份 `审计日志.jsonl`（schema 一致）
- 查询统一用 `安全审核.ps1 -Report`

### 4. 6 类 subagent（Claude 机制）

覆盖从需求到验证的全流程，由系统 Agent 在合适时机派出：

| subagent | 职责 |
|---|---|
| requirement | 梳理需求、痛点、边界、验收标准 |
| design | 设计文件结构、权限、同步、审计规则 |
| develop | 按设计修改文件、维护待办 |
| test | 验证可读性、引用一致性、权限流程 |
| skills | 检查/安装/登记 skills |
| git | git 操作 / GitHub / SSH |

详见各自 AI 工作区的 AGENTS.md / CLAUDE.md。

### 5. 待办制度

"项目级待办 + 根级全量聚合"模式：

- **项目级**：各项目 `待办.md` 统一字段（编号 / 短标题 / 一句话概述 / 优先级 / 限期 / 状态 / 登记日），编号 `{缩写}-NNN`
- **优先级**（重要×紧急矩阵）：P0 紧急且重要 / P1 重要不紧急 / P2 紧急不重要 / P3 不重要不紧急
- **根级聚合**：`Automation/regen_root_todos.py` 每天自动重建根级 `待办.md` 的"项目待办"章节（收录所有项目的未完成条目，按优先级分组排序）
- 根级 `待办.md` 还有"手记待办"章节——随手记录、扁平列表、零摩擦

标准模板和完整示例见 `Sample/待办.md`。

### 6. 变更标记规范

正文中的"最近一次变更"用三色标记标注，下次编辑该文件前先清旧标记：

| 标记 | 含义 |
|---|---|
| 🟡 | 改（修改了已有内容） |
| 🟢 | 增（新增了内容） |
| 🔴 | 删（删除了内容） |

详见 `md/变更标记规范.md`。

### 7. 每日自动化

`Automation/` 承载每日自动化，由 Windows 任务计划程序每天 22:00 触发：

| 产物 | 生成者 | 需要无头 CLI？ |
|---|---|---|
| 文件变更记录（`文件变更记录.md`） | `daily_changelog.sh`（git diff） | 否 |
| 待办聚合（`待办.md`「项目待办」节） | `regen_root_todos.py` | 否 |
| 简洁周报（`WorkRecord/每周工作总结.md`） | `daily_worklog.sh` | **是** |
| 详细述职（`WorkRecord/每周工作总结-详细.md`） | `daily_worklog.sh` | **是** |

工作总结用各 AI 自己的无头 CLI 读当天对话（+git 变更+完成待办）起草，详见 `Automation/README.md`。

---

## 目录结构

```text
agent-workspace/
├── README.md              # 本文件
├── .gitignore
├── Shared/                # 跨 AI 协作
│   └── 多AI交流.md
├── Codex/                 # Codex 完整工作区
│   ├── AGENTS.md          # Codex AI 手册
│   ├── hooks/             # check_s_level.ps1 + after_turn.ps1
│   ├── git-hooks/         # pre-commit / post-commit（→ 复制到 .git/hooks/）
│   ├── 安全审核.ps1        # 审计脚本（-Request/-Approve/-Log/-Report）
│   ├── 审计日志.jsonl      # 机器可读审计日志
│   ├── 待办.md / 文件变更记录.md
│   ├── .codex/            # 运行时配置（用户自建，参考 md/ 模板）
│   ├── Automation/ / WorkRecord/ / Sample/
│   ├── .backups/          # L0 文件备份
│   └── md/                # 画像映射表 / hooks策略 / config.toml.模板 / hooks.json.模板 / S级清单 / 文件权限系统 / 变更标记规范 / Skills / 审计记录
├── Claude/                # Claude 完整工作区
│   ├── CLAUDE.md          # Claude AI 手册
│   ├── hooks/             # check_permission + check_s_level + after_edit
│   ├── 安全审核.ps1 / 审计日志.jsonl / 待办.md / 文件变更记录.md
│   ├── .claude/           # settings.json + agents/（6 类 subagent）
│   ├── Automation/ / WorkRecord/ / Sample/
│   ├── .backups/          # L0 文件备份
│   └── md/                # 画像映射表 / hooks策略 / S级清单 / 文件权限系统 / 变更标记规范 / Skills / 审计记录
```

---

## 首次使用

### 1. 获取项目并建立自己的仓库

```bash
# 方式一：clone 后改为自己的仓库
git clone <repo-url> agent-workspace
cd agent-workspace

# 删除原作者的 git 历史，建立自己的
rm -rf .git
git init
git add -A
git commit -m "init agent-workspace"

# 添加自己的远程仓库并推送
git remote add origin <your-github-repo-url>
git branch -M main
git push -u origin main
```

```bash
# 方式二：直接复制目录后初始化
cd agent-workspace
git init
git add -A
git commit -m "init"
git remote add origin <your-github-repo-url>
git push -u origin main
```

### 2. 环境依赖

| 依赖 | 用途 | 必须？ |
|---|---|---|
| Git | 版本管理 + git hooks | 是 |
| Git Bash | Automation 的 `.sh` 脚本 | 是 |
| PowerShell 5.1+ | hooks 与 `安全审核.ps1` | 是 |
| Python 3.8+ | 待办聚合脚本（纯标准库） | 待办聚合需要 |
| 无头 CLI（`claude`/`codex`） | 工作总结功能 | 仅工作总结需要（见下） |

### 3. Claude Code 用户

```bash
cd Claude
git init
git add -A && git commit -m "init Claude workspace"
git remote add origin <your-claude-repo-url>
git push -u origin main
```

1. Claude Code 自动发现 `.claude/settings.json`，hooks 开箱即用
2. hooks 脚本自动检测工作区根目录（脚本在 `hooks/` 下，上一级即工作区根）
3. `.ps1` 脚本须以 **UTF-8 BOM** 保存（PS 5.1 兼容），出厂已带 BOM

### 4. Codex 用户

```bash
cd Codex
git init
git add -A && git commit -m "init Codex workspace"
git remote add origin <your-codex-repo-url>
git push -u origin main
```

1. 复制配置项到 `~/.codex/config.toml`（参考 `md/config.toml.模板`，**不复制 token/密钥**）
2. 创建 `.codex/hooks.json`（参考 `md/hooks.json.模板`）
3. 在 config.toml 中设 `[features] codex_hooks = true`
4. 复制 git hooks 到 `.git/hooks/`：
   ```bash
   cp git-hooks/pre-commit .git/hooks/pre-commit
   cp git-hooks/post-commit .git/hooks/post-commit
   chmod +x .git/hooks/*
   ```
5. 用 `codex auth` 登录（默认使用 OpenAI 账号认证）

### 5. 配置无头 CLI（工作总结功能）

工作总结依赖对应 Agent 的**无头 CLI**（Claude 用 `claude`、Codex 用 `codex`）已安装可登录。脚本读当天对话生成；CLI 不可用则跳过工作总结，不影响变更记录/待办聚合。

**各 AI 各自配置**（各自的 Automation/ 在各自工作区内）：

```bash
# Codex 侧
cd Codex
cp Automation/automation.conf.example Automation/automation.conf
# 编辑 automation.conf：CODEX_BIN / PROXY_PORT（可留空）

# Claude 侧
cd Claude
cp Automation/automation.conf.example Automation/automation.conf
# 编辑 automation.conf：CLAUDE_BIN / PROXY_PORT（可留空）
```

- `automation.conf` 已 gitignore（含本地路径不入库）
- **首次使用前务必先在终端跑一次 `codex login`（或 `claude` 登录）**，否则无头调用因无认证而失败
- **不配置则跳过工作总结**，文件变更记录和待办聚合不受影响
- 公司内部模型：在 `~/.codex/config.toml` 配 `model_provider`/`model`/`base_url` 即可

### 6. 注册每日定时任务

```powershell
# 在各 AI 工作区内分别注册
cd Codex  # 或 Claude
powershell -ExecutionPolicy Bypass -File Automation/register_task.ps1
```

默认每天 22:00 触发。

### 7. 配置 S 级清单（如需跨 AI 文件隔离）

编辑各自 `md/S级清单.md`，在 ` ```paths ` 代码块中填入**对方 AI** 的 S 级路径（相对自己的工作区根目录）。S 级文件同时需列入各自 `.gitignore`。

### 8. 验证测试

首次构建后建议测试：

- **Codex**：运行 `.\安全审核.ps1 -Report` 确认审计脚本可运行
- **Claude**：在 `Claude/` 下启动 Claude Code，编辑一个 L2 文件，确认 hook 自动审计 + commit
- **S 级拦截**：在 S 级清单中填入一个测试路径，尝试通过 Bash/Read 访问，确认被 deny

---

## 日常使用

### AI 修改文件

变更权限（L0/L1/L2）控制的是 **AI 修改文件**时的审批要求：

| 文件级别 | AI 修改方式 |
|---|---|
| L2（普通） | 直接改。Claude: hook 自动审计+commit；Codex: `git add && git commit` |
| L1（指令文件） | Claude: hook 弹窗批准；Codex: `安全审核.ps1 -Request` → `-Approve` → 改 → `-Log` |
| L0（制度/删除） | 双确认+备份+tag。Codex: `安全审核.ps1 -Request` 自动备份+打 tag |

### 人类修改文件

人类是权限的授予者，不受 L0/L1/L2 限制，可以直接修改任何文件。但 git hooks（pre-commit/post-commit）对**所有提交**生效——无论是 AI 还是人类提交，都会经过 pre-commit 的 L0/L1 检查和 post-commit 的审计日志写入。

### 切换画像

修改 `config.toml`（Codex）或切换 permission mode（Claude），详见各自 `md/画像映射表.md`。

### 查审计

```powershell
.\安全审核.ps1 -Report        # 全部审计记录
.\安全审核.ps1 -Last 10       # 最近 10 条
```

### 手动跑自动化

```bash
# 当日总结
TODAY=2026-01-01 bash Automation/daily_run.sh

# 重建根级待办
python Automation/regen_root_todos.py
```

---

## 注意事项

1. **`.ps1` 脚本必须 UTF-8 BOM**：PS 5.1 不加 BOM 会导致中文乱码或脚本崩溃。出厂已带 BOM，手动编辑后需确认未丢失。

2. **Codex hooks 只匹配 Bash**：Codex 的 PreToolUse/PostToolUse 仅匹配 `Bash`/`shell_command`，不拦截 Edit/Write/Read。文件编辑的权限检查靠 git pre-commit + `安全审核.ps1` 手动流。

3. **Codex sandbox 无 per-path denyRead**：S 级读取拦截靠 `check_s_level.ps1`（PreToolUse on Bash），是 best-effort 而非 OS 级硬隔离。

4. **"Approve for me" ≠ auto 画像**：UI 的"替我审批"是放弃审批=无脑放行。auto 画像是"越界无人批=拦"。

5. **bypass 画像的 S 地板**：bypass = `danger-full-access` + `never`，hook 仍执行；部署后请自行确认所在环境实际行为。

6. **自动注入盲区**：CLAUDE.md / AGENTS.md / memory / SessionStart 等自动加载的内容不是 Read/Bash 调用，hook 拦不到。S 级文件不得放入自动加载位置——约定强制，非技术强制。

7. **Automation 工作总结需对应无头 CLI 可用**：不配置则跳过工作总结，文件变更记录和待办聚合不受影响。

8. **文件层强制不对称**：Claude PreToolUse 编辑前拦截（文件没改就被挡）；Codex git pre-commit 提交前拦截（文件已改但进不了 git 历史）。

---

## 相关文件

### 入口文件

| 文件 | 给谁 | 用途 |
|---|---|---|
| `README.md`（本文件） | 人 | 项目介绍与使用指南 |
| `Codex/AGENTS.md` | Codex AI | Codex 工作区根级手册 |
| `Claude/CLAUDE.md` | Claude AI | Claude 工作区根级手册 |

### 权限与治理

| 文件 | 位置 | 内容 |
|---|---|---|
| `文件权限系统.md` | 各 `md/` | L0/L1/L2 变更权限 + S/P 阅读等级完整制度 |
| `画像映射表.md` | 各 `md/` | 5 画像 → 原生模式映射 + 三维写判定 + 令牌机制 |
| `hooks策略.md` | 各 `md/` | hook 体系 + S 级拦截 + 不对称说明 |
| `变更标记规范.md` | 各 `md/` | 三色标记规则 |
| `S级清单.md` | 各 `md/` | 对方 AI 的 S 级路径清单 |
| `安全审核.ps1` | 各工作区根 | 审计脚本（-Request/-Approve/-Log/-Report） |

### 配置模板

| 文件 | 位置 | 内容 |
|---|---|---|
| `config.toml.模板` | `Codex/md/` | Codex 配置模板（含画像预设） |
| `hooks.json.模板` | `Codex/md/` | Codex hooks 配置模板 |
| `automation.conf.example` | 各 `Automation/` | 无头 CLI 配置示例 |

### 协作与示例

| 文件 | 位置 | 内容 |
|---|---|---|
| `多AI交流.md` | `Shared/` | 跨 AI 讨论与共识记录 |
| `Sample/` | 各工作区 | 示例项目（AGENTS.md + 待办.md），供参考构建 |
| `WorkRecord/` | 各工作区 | 每周工作总结模板 |
| `Automation/README.md` | 各 `Automation/` | 自动化详细说明 |

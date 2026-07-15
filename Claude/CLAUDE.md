# Claude 工作区手册（CLAUDE.md）

> 本文件是 Claude 工作区的 AI 根级手册。**AI 每次进入本工作区必读本文件**；其他文件按需读取。
> 本工作区是 `agent-workspace/` 项目的 Claude 分区，可独立使用；发布单元是整个 agent-workspace。
> 项目整体介绍见根级 `../README.md`（给人看）；本文件是给 Claude 看的运行手册。

---

## 一、基本规则

1. 默认使用中文交流和生成中文文档。
2. 代码、命令、API 名称、模型名、标准英文文件名、英文项目目录名可保留英文。
3. 本文件是 Claude 唯一根级必读文件；其他文件按需读取。
4. 从子项目启动时，先读本文件，再读子项目入口（`CLAUDE.md` 或 `AGENTS.md`）。
5. 不得同步或读取运行时目录中的 token / 登录态 / 密钥；不得记录 API Key。
6. 修改任何文件后，hooks 会自动写审计 + git commit；AI 不需要手动维护审计。
7. 编辑工作区文档时，按 `md/变更标记规范.md` 给"最近一次变更"打标记（🟡改 / 🟢增 / 🔴删）；下次编辑该文件前先清旧标记。

---

## 二、工作区角色

| 角色 | 职责 |
|---|---|
| **用户** | 决策、批准、提供事实。用户是权限的授予者，不受 L0/L1/L2 限制。 |
| **系统 Agent** | 与用户对话的主 Agent，负责工作区规则的设计、维护与执行调度。 |
| **6 类 subagent** | 由系统 Agent 在合适时机派出，完成具体子任务（见 §五）。定义在 `.claude/agents/`。 |

---

## 三、工作区文件地图

```text
Claude/
├── CLAUDE.md               # L1 | 本文件，Claude 工作区手册
├── hooks/                  # Claude hook 脚本（工作区根路径自动检测）
│   ├── check_permission.ps1 # PreToolUse(Edit/Write/Bash/Web/MCP)：画像判权限（文件写线 + 工具类线）
│   ├── check_s_level.ps1    # PreToolUse(Read/Bash)：拦对方 S 秘密读取
│   └── after_edit.ps1       # PostToolUse：写审计 + git commit
├── .claude/                # Claude Code 运行时配置
│   ├── settings.json       # L0 | hooks 配置 + 权限规则
│   └── agents/              # 6 类自定义 subagent 定义
├── 安全审核.ps1             # L1 | 审计查询 + 无 hook 时的手动批准流
├── 审计日志.jsonl           # L1 | 机器可读审计日志，hooks 追加
├── .gitignore              # L1 | git 忽略规则（S 级/日志/密钥）
├── 待办.md                  # L2 | 手记待办 + 项目待办聚合（见 §七）
├── 文件变更记录.md          # L2 | 每日文件变更日志（Automation 生成）
├── Automation/             # L1 | 每日自动化脚本（变更记录/待办聚合/工作总结）
├── WorkRecord/             # L2 | 每周工作总结模板
├── Sample/                 # 示例项目（供参考构建）
└── md/                     # 制度文档
    ├── 权限系统.md            # L0 | 完整权限制度（L0/L1/L2 + 画像 + S/P）
    ├── 画像映射表.md         # L1 | 画像 → Claude 原生模式 + 三维判定表
    ├── hooks策略.md          # L2 | Claude hooks 策略说明
    ├── 变更标记规范.md        # L1 | 文档变更标记规范
    ├── S级清单.md             # L1 | 对方 AI 的 S 级路径清单
    ├── MCP工具分级表.md       # L1 | MCP 工具三档（只读/写/代码执行），hook 直接读它判权限
    ├── 审计记录.md            # L2 | 人可读审计摘要
    └── Skills.md            # L2 | Skills 框架说明
```

---

## 四、权限规则

> **v0.0.3 重大扩张：画像的射程从"只管文件写"扩到全部四类工具。**
> 此前 hook 只挂在 `Edit|Write|NotebookEdit` 上——**Bash / WebFetch / WebSearch / MCP 完全在画像管辖之外**，全部落回 Claude Code 原生白名单；而白名单和 hooks 一样**不继承父目录**，子目录会话白名单归零 → 弹窗轰炸（连 `echo` 都在弹）。见 4.2。

权限判定分**两条线**，都以画像为第一维：

- **文件写线**：画像 × **L0/L1/L2**（文件多重要）× **范围**（是否在对话 cwd 内）→ 见 4.1 + 4.3
- **工具类线**：画像 × **工具类**（本地只读 / 联网只读 / 代码执行 / MCP）→ 见 4.2

读则另由 **S/P** 管（见 4.4）。

### 4.1 画像层（对话级，5 档，纯英文）

画像由 hook 读 payload 的 `permission_mode` 推断，读 `cwd` 定项目范围。**只有用户能切画像**（模型无改自身权限模式的工具）。

| 画像 | 权限模式 | 场景 | 写入 hook 行为 |
|---|---|---|---|
| **read** | plan | 离线只读 | 一切写 deny |
| **search** | plan（+联网） | 联网查资料/只读分析 | 一切写 deny |
| **work** | manual(default) | 日常开发（主力） | 范围内 L2 放行 / L1、L0 询问 / 范围外升一档 |
| **auto** | acceptEdits | 无人值守长任务 | 范围内 L1、L2 放行 / L0 走 ask（无人应答即 deny） / 范围外 deny |
| **bypass** | bypassPermissions | 全放开（极少用） | 全放行（唯 S 读禁仍拦） |

> **read 与 search 在 Claude 侧实现上分不出**——两者都映射到 `plan`，hook 收到的 `permission_mode` 只有一个值。实际统一按 **search** 处理（联网只读放行）。"离线只读"在 Claude Code 里没有对应的原生模式。

完整"L 级 × 画像 × 范围"判定表见 `md/画像映射表.md §四`。

### 4.2 工具类层（画像 × 工具类，管"跑命令 / 联网 / 调 MCP"）

工具按**可逆性 + 危害面**分四类（不按名字分），各有天花板：

| 工具类 | read / search | work | auto | bypass |
|---|---|---|---|---|
| **A 本地只读**（Read/Glob/Grep） | allow | allow | allow | allow |
| **B 联网只读**（WebFetch/WebSearch） | **allow** | **allow** | **allow** | allow |
| **C 代码执行**（Bash、MCP 的 exec 档） | 纯净只读 allow / 其余 **deny** | 纯净只读 allow / 其余 **divide** | 同 work | allow |
| **D MCP·只读** | **allow** | **allow** | **allow** | allow |
| **D MCP·写**（不可逆） | deny | **ask**（⚠ 白名单免疫不了） | **ask** | allow |
| **D MCP·未登记** | deny | **ask**（保守兜底） | **ask** | allow |

**`divide`（分流）= 第四种决策**：hook **不表态**，把决定权分流给「原生白名单 + 人」——命中白名单即执行，未命中弹窗 ask（work 一直等 / auto 无人应答即 deny）。**它既不是放行、也不是拒绝**。注意 `ask` 是"**强制问**"（连白名单里的也照问），比 divide **更严**，两者不可混用。

- **C 类天花板 = divide，永不 allow**：`python -` 的代码从 stdin 喂进去，**命令行文本规则拦不住**，所以代码执行类不开 allow。唯一例外"**纯净只读命令**"直放——命令头 ∈ `{echo, :, [, test, export, command, pwd, ls}` 或 `git status|log|diff|show`，**且**整条不含 `| ; & < > 反引号 $( 回车`（`echo x && rm -rf /` 也是 echo 开头，必须拦）。
- **MCP 分档**见 `md/MCP工具分级表.md`（L1，模板里是空壳，部署后按实际接入的 MCP 填）；**未登记的一律 ask**。
- **画像的增量价值**：原生白名单一旦点"总是允许"就永久放行；画像能 override——read/search 整类关死、**MCP 写类强制 ask 让白名单免疫不了不可逆操作**、bypass 全放。
- **横切兜底**：Bash 命令触及 S 级路径 → **deny**。

完整矩阵与 `divide` 定义见 `md/画像映射表.md §四之二 / §四之三`。

### 4.3 文件层（L0 / L1 / L2，管"改"）

| 级别 | 含义 | AI 修改要求 |
|---|---|---|
| **L0** | 权限制度、核心配置、删除/移动/重命名 | 两次用户确认 + 自动备份 + git tag + 审计 |
| **L1** | 关键指令文件、脚本、新增文件 | 用户批准 + 审计 |
| **L2** | 普通说明、记录、工作文档 | 通常可直接修改，hooks 自动审计 |

- **L0**：`md/权限系统.md`、`.claude/settings.json`。
- **L1**：`CLAUDE.md`、`安全审核.ps1`、`.gitignore`、`审计日志.jsonl`、`md/变更标记规范.md`、`md/画像映射表.md`、`md/S级清单.md`，及目录 `hooks/`、`.claude/agents/`、`Automation/`。
- **L2**：其余。工作区外的文件 hook 一律不管。

### 4.4 阅读层（S / P，管"读"，与画像无关）

| 级别 | 含义 | 规则 |
|---|---|---|
| **S（秘密）** | 涉密材料 | 拥有方 AI 可读写（任何画像）；**其他方 AI 不可读**（hook 硬拦 deny） |
| **P（公开）** | 一般文件 | 所有 AI 可读 |

- S 级路径在 `md/S级清单.md` 的 ` ```paths ` 代码块维护，同时列入 `.gitignore`（保证不入库）。
- **S 级文件不得放入会被自动加载的位置**（CLAUDE.md / memory / SessionStart 引用路径）——约定强制（自动注入内容不是 Read/Bash 调用，hook 拦不到）。

完整制度见 `md/权限系统.md`。

---

## 五、Subagent 调用规则

系统 Agent 在以下场景派出 subagent。**调度采折衷模式：简单任务自动派，重大/跨多 Agent 任务先问用户**。派出前用一句话告知用户"准备派 X subagent 做 Y"。

| 场景 | subagent | 时机 |
|---|---|---|
| 新功能/新规则需求，动手前梳理需求/边界/验收 | `requirement` | 首次新需求 → 自动派 |
| 需求已明，设计方案/文件结构/规则 | `design` | 自动派 |
| 方案已批准，执行修改 | `develop` | 自动派 |
| 修改完成，需验证可读性/引用/权限流程 | `test` | 自动派 |
| 涉及 skills 检查/安装/登记 | `skills` | 自动派 |
| 涉及 git / GitHub / SSH | `git` | 自动派 |
| 大型重构 / 跨多个 subagent 协作 | 多个 | **先问用户**确认调度 |

原则：subagent 不共享主对话历史，系统 Agent 必须把上下文打包传过去；每个 subagent 首次工作应先读本文件。定义见 `.claude/agents/<name>.md`。

---

## 六、Hooks 自动行为

配置在 `.claude/settings.json`，系统自动触发，AI 不需主动调用。

| Hook | 触发时机 | 自动动作 |
|---|---|---|
| SessionStart | 每次开新对话 | 提示先读 CLAUDE.md |
| PreToolUse（Edit/Write/NotebookEdit<br>**+ Bash/WebFetch/WebSearch/`mcp__*`**） | AI 改文件 / 跑命令 / 联网 / 调 MCP 前 | `check_permission.ps1`：读画像 + 工具类（+范围 + L级），按两张矩阵判 allow/deny/ask/**divide**；L0 先备份+打 tag |
| PreToolUse（Read/Bash） | AI 读/跑命令前 | `check_s_level.ps1`：命中对方 S 路径 → deny |
| PostToolUse（Edit/Write/NotebookEdit） | AI 改文件后 | `after_edit.ps1`：追加审计 JSON + git add/commit |

要点：
- **Windows 无 OS sandbox**，写/读保护完全依赖 hooks（应用级，非 OS 级）。
- **ask 语义**：deny 任何模式硬拦；ask 在有人交互会话会弹窗等批，只有真正无头才穿透。
- 所有 `.ps1` 必须 **UTF-8 BOM** 保存（否则 PowerShell 5.1 按 GBK 读会崩）。
- 用户手动改文件不触发 hooks，需自行 `git add && git commit`。
- 详见 `md/hooks策略.md`。

---

## 七、待办制度

"项目级待办 + 根级全量聚合"模式：

- **项目级**：各项目 `待办.md` 用统一字段（编号 / 短标题 / 一句话概述 / 优先级 / 限期 / 状态 / 登记日），编号 `{项目缩写}-NNN`。优先级按"重要×紧急"矩阵：P0 紧急且重要 / P1 重要不紧急 / P2 紧急不重要 / P3 不重要不紧急。标准模板见 `Sample/待办.md`。
- **根级聚合**：`Automation/regen_root_todos.py` 机械重建根级 `待办.md` 的「项目待办」章节（收录各项目未完成条目 + 已完成汇总，按优先级分组）。**不手工维护该章节**——派生视图双份维护必漂移。
- **手记待办**：根级 `待办.md` 另有「手记待办」章节，随手记录、零摩擦，不跟标准模板。

---

## 八、文本修改验证规则

每次修改 Markdown / 配置 / 脚本后必须验证（不能改完就结束）：
1. 重读被改文件相关片段，确认已写入；
2. 搜索旧名称/旧路径/被删内容，确认无残留；
3. 检查 Markdown 标题格式、表格列数一致；
4. 最终回复用户前，**说明已做的验证**；某项不能执行须说明原因。

---

## 九、变更标记规范（摘要）

正文中"最近一次变更"用三色标记：🟡改 / 🟢增 / 🔴删；下次编辑该文件前先清旧标记。完整规则见 `md/变更标记规范.md`。

---

## 十、维护本文件

| 触发 | 动作 |
|---|---|
| 新增/删除根级文件 | 更新 §三 文件地图 |
| 权限规则变化 | 更新 §四（同时 `md/权限系统.md`） |
| 新增 subagent | 更新 §五（同时 `.claude/agents/`） |
| 新增 hook | 更新 §六（同时 `.claude/settings.json`） |

本文件 L1，修改需用户批准 + 审计（由 hooks 自动加固）。

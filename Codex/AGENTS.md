# Codex 工作区 AGENTS

> 本文件是 Codex 工作区的 AI 手册。进入本工作区前先读根目录 `../README.md`（项目介绍与使用指南），
> 再读本文件（Codex 专属规则），最后按任务需要读取项目 `AGENTS.md`。

---

## 一、基本规则

1. 默认使用中文交流和生成中文文档。
2. 代码、命令、API 名称、模型名可保留英文。
3. 本文件是 Codex 工作区必读文件；其他文件按需读取。
4. 不得读取 `.codex` 中的 token、登录态、密钥；不得记录 API Key。
5. 修改任何文件后，hooks 会自动写审计 + git commit；AI 不需要手动维护审计。
6. 编辑工作区文档时，按 `md/变更标记规范.md` 给"最近一次的变更"打标记（🟡改 / 🟢增 / 🔴删）；下次编辑该文件前先清旧标记。
7. <span style="color:#228B22">🟢 每次工作**先读本侧 `待同步.md`**（变更请求收件箱：使用本模板的下游实际工作区会话把该改的事交办到这里）。挑"待处理"条目落地后：实际改 → 写 `../Releases.md` / `../变更详情.md` → 把该条状态改"已落地（vX.X.X）"并移入其存档表 → commit / push。</span>

---

## 二、工作区文件地图

```text
Codex/
├── AGENTS.md              # L1 | 本文件，Codex 专属手册
├── hooks/                # Codex hook 脚本（check_s_level + after_turn）
├── git-hooks/              # git hook 脚本（→ 复制到 .git/hooks/）
│   ├── pre-commit          # 检查 L0/L1 未批准变更
│   └── post-commit         # 自动写审计日志
├── 安全审核.ps1             # L1 | 审计辅助脚本
├── 审计日志.jsonl           # L1 | 机器可读审计日志
├── 待办.md                  # L2 | 手记待办 + 项目待办聚合
├── 文件变更记录.md          # L2 | 文件变更日志
├── .gitignore              # L1 | git 忽略规则（S 级/日志/密钥）
├── .codex/                 # Codex 运行时配置（config.toml、hooks.json）
├── Automation/             # 每日自动化
├── WorkRecord/             # 工作记录
├── Sample/                 # 示例项目
└── md/                     # 制度文档
    ├── 画像映射表.md         # L1 | 画像 → Codex 原生模式映射
    ├── hooks策略.md          # L2 | Codex hooks 策略说明
    ├── config.toml.模板     # L0 | config.toml 配置模板（脱敏）
    ├── hooks.json.模板       # L0 | .codex/hooks.json 配置模板
    ├── S级清单.md            # L1 | 对方 AI 的 S 级路径清单
    ├── 审计记录.md            # L2 | 人可读审计摘要
    ├── 文件权限系统.md        # L0 | 完整权限制度
    ├── 变更标记规范.md        # L1 | 文档变更标记规范
    └── Skills.md            # L2 | Skills 框架说明
```

---

## 三、终端识别

用 `COMPUTERNAME` 和 `USERNAME` 判断当前终端。如果无法匹配，必须询问用户当前终端，不得猜测。

---

## 四、Codex 权限规则

### 沙箱层（画像）

| 画像 | sandbox_mode | approval_policy | network | 场景 |
|---|---|---|---|---|
| read | read-only | never† | false | 离线只读 |
| search | read-only | never† | true | 联网只读 |
| work | workspace-write | on-request | true | 日常开发 |
| auto | workspace-write | on-request | true | 无人值守 |
| bypass | danger-full-access | never | true | 全放开 |

> † `never` + `read-only`：Codex 回退到 "read-only + approvals disabled" = 真只读。
> work 与 auto 的 config 相同，区别在使用场景（有人/无人应答审批请求）。

详见 `md/画像映射表.md`。

### 文件层（L0/L1/L2）

见本工作区 `md/文件权限系统.md`。

### Codex 原生 hooks

- 配置：`.codex/hooks.json` + `config.toml` 中 `[features] codex_hooks = true`
- PreToolUse/PostToolUse **仅匹配 Bash**，不匹配 Edit/Write/Read
- 文件编辑审计改用 git hooks（pre-commit/post-commit）+ Stop hook
- S 级读取拦截：`hooks/check_s_level.ps1`（PreToolUse on Bash → deny）
- 详见 `md/hooks策略.md`

---

## 五、文本修改验证规则

每次修改文件后，必须：
1. 重新读取被修改文件片段，确认内容写入
2. 搜索旧名称/旧路径，确认无残留
3. 检查 Markdown 标题格式（`#`/`##`，无伪标题）
4. 检查 Markdown 表格列数一致
5. 最终回复前说明已完成哪些验证

---

## 六、审计记录组织

`审计记录.md` 按周/日组织：`## 第N周` → `### 日期` → 独立表格。

---

## 七、待办制度

工作区实行"项目级待办 + 根级全量聚合索引"模式。

### 7.1 分工

| 层级 | 文件 | 维护方式 | 权威性 |
|---|---|---|---|
| 各项目 | `待办.md`（统一命名） | 各项目自行维护，权威来源 | ✅ 权威 |
| 根级 | `待办.md`（"手记待办"+"项目待办"两章节） | "手记待办"人工维护；"项目待办"由 `Automation/regen_root_todos.py` 机械重建 | 手记✅权威；项目待办❌非权威仅快照 |

### 7.2 标准模板（项目级）

各项目 `待办.md` 统一字段：

| 编号 | 短标题 | 一句话概述 | 优先级 | 限期 | 状态 | 登记日 |
|---|---|---|---|---|---|---|

高信息量条目在"备注"区展开来龙去脉，不放进表格行。完整示例见 `Sample/待办.md`。

**编号**：`{项目缩写}-{三位数字}`，如 `SP-001`，项目内独立递增。

**项目缩写登记表**：

| 项目 | 路径 | 缩写 |
|---|---|---|
| Sample | `Sample/` | `SP` |

新增项目时在此登记缩写。

**优先级**（重要×紧急矩阵）：

| 代码 | 含义 | 处理方式 |
|---|---|---|
| P0 | 紧急且重要 | 尽快转正式任务；被搁置需在备注写清卡在什么外部依赖 |
| P1 | 重要不紧急 | 待办体系重点守护对象；限期临近升 P0 |
| P2 | 紧急不重要 | 抓窗口顺手做，窗口过可作废 |
| P3 | 不重要不紧急 | 有空再看，长期挂着无妨 |

P1 排在 P2 之前：紧急的事本身有时间压力推着走，真正需要这份文档盯着、怕遗忘的，是重要不紧急的事。

**已完成**：独立存档表，放文件最后，字段 `编号|短标题|一句话概述|优先级|登记日|完成日`，按完成日倒序。

### 7.3 根级"手记待办"

根级 `待办.md` 的"手记待办"章节是随手记录区：扁平列表（不按主题/日期分组），一条待办一行：

- 行首写**登记日期**（`YYYY-MM-DD`）
- `[ ]` 未完成 / `[x]`✅完成日 已完成 / `[-]` 放弃或不再做
- 新的加在**上面**（最新在最上）

### 7.4 根级"项目待办"

- 收录各项目"待办总表"的全部未完成条目 + 末尾跨项目"已完成"汇总（各项目"已完成"表的只读镜像，按项目分组、组内完成日倒序）。
- 展示顺序：按优先级分组（P0→P1→P2→P3），组内按限期/登记日排序。
- 由 `Automation/regen_root_todos.py` 机械重建；每天 22:00 自动跑一次并 `git commit`，另可随时手动。
- **不手工维护本节**——派生视图双份维护必漂移。脚本只重写"## 项目待办"这一节，不触碰"## 手记待办"章节。

---

## 八、子项目索引

| 项目 | 路径 | 入口 |
|---|---|---|
| Sample | `Sample/` | `Sample/AGENTS.md` |

新增子项目时在此补一行。子项目启动读取顺序：先读本文件（`AGENTS.md`）→ 再读当前项目 `AGENTS.md` → 最后按需读取版本、阶段、需求、设计、测试等专属文件。

---

## 九、Automation 自动化

`Automation/` 承载每日自动化，由 Windows 任务计划程序每天 22:00 触发。详见 `Automation/README.md`。

| 产物 | 位置 | 生成者 |
|---|---|---|
| 文件变更记录 | `文件变更记录.md` | `daily_changelog.sh` |
| 待办聚合 | `待办.md`（仅"## 项目待办"节） | `regen_root_todos.py` |
| 简洁周报 | `WorkRecord/每周工作总结.md` | `daily_worklog.sh` |
| 详细述职 | `WorkRecord/每周工作总结-详细.md` | `daily_worklog.sh` |

工作总结用无头 codex 读当天对话（+git 变更+完成待办）起草，详见 `Automation/README.md`。
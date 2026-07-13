# Claude Hooks 策略

> Claude Code 通过 `.claude/settings.json` 配置 PreToolUse/PostToolUse/SessionStart hooks，
> 在工具调用前/后自动做权限判定、S 级读拦截、审计与 git commit。
> 权属：Claude 侧维护。

## 一、hook 总览

| 事件 | 匹配 | 脚本 | 行为 |
|---|---|---|---|
| SessionStart | * | echo 提示 | 进入工作区提示先读 CLAUDE.md |
| PreToolUse | Edit\|Write\|NotebookEdit | check_permission.ps1 | 按画像 + 范围 + L 级判 allow/ask/deny（写保护） |
| PreToolUse | Read\|Bash | check_s_level.ps1 | 命中对方 S 路径 → deny（读隔离） |
| PostToolUse | Edit\|Write\|NotebookEdit | after_edit.ps1 | 写审计日志 + git add/commit |

所有 `.ps1` **必须 UTF-8 BOM 保存**（否则 Windows PowerShell 5.1 按 GBK 解析崩溃）。

## 二、check_permission.ps1（写保护，已画像化）

读三样东西判一次写：**permission_mode**（定画像 read/search/work/auto/bypass）＋ **cwd**（定项目范围：目标是否在 cwd 子树内）＋ **目标文件 L 级**（L0/L1/L2）。

- level 映射：L0（文件权限系统.md、settings.json）/ L1（CLAUDE.md、安全审核.ps1、.gitignore、审计日志.jsonl、变更标记规范.md、画像映射表.md、S级清单.md，及 `hooks/`、`.claude/agents/`、`Automation/` 目录）/ L2（其余）。工作区外文件一律放行。
- 判定：read/search → 一律 deny；work → 范围内 L2 allow、L1/L0 ask、范围外升一档；auto → 范围内 L1/L2 allow、L0 凭一次性令牌否则 deny、范围外 deny；bypass → 一律 allow（S 读禁另拦）。完整表见 `md/画像映射表.md §四`。
- L0 且结果非 deny：先自动备份（滚动留 10 份）+ 打 git tag。
- 画像读不到（老版本无 `permission_mode` 或未知值）→ 兜底当 work。

## 三、check_s_level.ps1（读隔离，已生效）

- 目标：堵两条读对方 S 的路子——Read 工具直读、Bash（`cat`/`Get-Content`）读。PreToolUse 同时匹配 `Read|Bash`，命中 `md/S级清单.md` 的对方 S 路径就 deny。
- 从 S 清单的 ` ```paths ` 代码块（**3 反引号**围栏）读路径，归一化为绝对路径 + 正/反/双反斜杠三变体匹配。
- **自检**：若读到 0 条路径但清单里确有 paths 围栏 → 往 stderr 写 WARNING，避免"静默失效"。（提取 paths 的正则围栏必须与清单一致用 **3 个反引号**——反引号数不对会 0 命中＝假防线，此自检就是防这个。）
- Windows 无 OS 沙箱、无 `denyRead`，S 读隔离**完全靠此 hook 一层** + `.gitignore` 不入库 + 约定。

### 两个盲区
1. **Bash 读绕过**：已由 `Bash` matcher 覆盖。
2. **自动注入上下文**：CLAUDE.md/memory/SessionStart 注入的内容不是 Read/Bash 调用，hook 拦不到。**纯约定**（不做 lint）：S 级文件不得放入会被自动加载的位置（见 `md/S级清单.md` 规则 3）。

## 四、S 清单机制
- 独立文件 `md/S级清单.md`，含机器可读 ` ```paths ` 代码块（每行一路径，`#` 注释）+ 人类可读说明。
- **S 清单 ≠ .gitignore**：S 路径要同时进 .gitignore（保证不提交），但 .gitignore 还含日志/临时等非 S 项，两者分开维护、保持同步。
- **公开模板里 paths 块留占位/空**；真实 S 路径只在各自"实际工作区"填，不随公开模板发布。

## 五、文件层强制不对称（跨 AI 对齐用）
- Claude PreToolUse：**编辑前**拦（deny → 文件没被改）。
- Codex git pre-commit：**提交前**拦（文件已改在磁盘、进不了 git）。二者不等价——两边文档都写明。

## 六、部署到你的实际工作区
- 三个 `.ps1` 放 `hooks/`，`.claude/settings.json` 配好三个 matcher（见 §一），`.ps1` 保持 UTF-8 BOM。
- 改 `.claude/settings.json` 属 L0，按你的权限流程确认；hook 在会话启动时加载，改完需**新开会话**才生效（"S 读 deny 实测"须在新会话做）。
- 按你实际工作区的文件集，核对 `check_permission.ps1`/`after_edit.ps1` 的 L 级清单（须与 `md/文件权限系统.md §3.1` 一致）。

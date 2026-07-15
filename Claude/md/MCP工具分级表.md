# MCP 工具分级表

> 本文件被 `hooks/check_permission.ps1` **直接读取**，用于判定每个 MCP 工具属于哪一档，进而按画像矩阵决定放行 / 询问 / 分流。
> 文件级别 **L1**（改它等于改放行范围，需用户批准 + 审计）。
> 格式仿 `md/S级清单.md`：三个围栏代码块，每行一个工具名，`#` 开头为注释。
>
> **本文件在模板中是空壳** —— 三个围栏都没有条目。部署到你自己的工作区后，按你**实际接入的 MCP server** 填写。
> 不填也能跑：未登记的工具会先走 §三 的模式兜底；模式也匹配不上的一律 **ask**（保守，绝不默认放行）。

---

## 一、三档定义

| 档 | 含义 | 画像矩阵下的待遇 |
|---|---|---|
| **readonly**（只读） | 查、取、列、读、导航、抓页面文本。**不改变任何状态** | plan / work / auto → **allow**（不弹窗） |
| **write**（写） | 建、改、删、加、合并、上传、安装、发布。**不可逆或改变外部状态** | work / auto → **ask**（⚠ **白名单免疫不了**：哪怕手滑点过"总是允许"，仍每次问）；plan → deny |
| **exec**（代码执行） | 能执行任意代码 / 启动进程（浏览器里跑 JS、跑脚本、起 dev server） | **等同 Bash**：work / auto → **divide**（分流给白名单 + 人）；plan → deny。**天花板 = 永不 allow** |

**未在本表列出的 MCP 工具**：脚本先按 §三 的模式自动判档；模式也匹配不上的 → **ask**（保守兜底）。

---

## 二、已登记工具（按你自己接入的 MCP 填写）

> 三个围栏的格式必须保持（脚本靠 ` ```readonly ` / ` ```write ` / ` ```exec ` 三个围栏名定位）。
> 工具名写全称，形如 `mcp__<server>__<tool>`。

### 只读（readonly）

```readonly
# 每行一个工具全名，例如：
# mcp__<server>__<tool>_search
# mcp__<server>__<tool>_get_item
# mcp__<server>__browser_navigate
```

### 写（write）—— ⚠ 恒 ask，白名单免疫不了

```write
# 不可逆 / 改变外部状态的工具，例如：
# mcp__<server>__<tool>_delete_item
# mcp__<server>__<tool>_update_item
# mcp__<server>__<tool>_create_note
```

### 代码执行（exec）—— 等同 Bash，天花板 divide，永不 allow

```exec
# 能执行任意代码 / 启动进程的工具，例如：
# mcp__<server>__browser_evaluate      （浏览器里跑任意 JS）
# mcp__<server>__run_code              （跑任意脚本）
# mcp__<server>__preview_start         （起 dev server = 执行命令）
```

---

## 三、模式兜底（表里没有的工具，脚本按此自动判档）

脚本先查上面的表；表里没有的，按工具名做模式匹配，**顺序从严到宽，不可颠倒**：

| 顺序 | 模式（工具名含） | 判为 |
|---|---|---|
| 1 | `evaluate` / `run_code` / `_exec` / `execute` / `preview_start` / `preview_stop` | **exec** |
| 2 | `_create` / `_update` / `_delete` / `_remove` / `_add_` / `_write` / `_merge` / `_batch` / `_install` / `_publish` / `_push` / `_upload` / `_submit` / `_click` / `form_input` | **write** |
| 3 | `_search` / `_get_` / `_list` / `_read` / `_fetch` / `_find` / `_query` / `navigate` / `snapshot` / `page_text` / `tabs_context` / `_status` / `_detect` / `_check` / `_resolve` | **readonly** |
| 4 | 都不匹配 | **ask**（保守兜底，绝不默认放行） |

**顺序不能反**：像 `browser_run_code_unsafe` 这种同时含多个关键词的，必须先判 exec。

---

## 四、维护

| 触发 | 动作 |
|---|---|
| 接入新 MCP server | 把它的工具按三档补进本表；**拿不准的不要列**（走兜底 ask 更安全） |
| 发现某工具被误判（该问的没问 / 不该问的老问） | 在本表**显式列出**它 —— 表优先于模式匹配 |
| 三档定义或矩阵变化 | 同步 `md/权限系统.md §二·补二`、`md/画像映射表.md §四之二` |

**原则**：宁可多问一次，不可错放一次。拿不准就别写进 `readonly`。

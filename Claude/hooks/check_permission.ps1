# ============================================
# PreToolUse hook: 画像 x 工具类 权限判定 (工作区唯一决策点)
# 触发: Edit / Write / NotebookEdit / Bash / WebFetch / WebSearch / mcp__*
#
# 画像 = payload.permission_mode
#   plan -> plan   (read 与 search 都是 plan, hook 天生分不出, 统一按 search 处理: 联网只读放行)
#   default -> work | acceptEdits|auto -> auto | bypassPermissions -> bypass | 缺失/未知 -> work(兜底)
#
# 工具分四类, 各有天花板:
#   [文件写] Edit/Write/NotebookEdit : 画像 x 范围(是否在 cwd 子树) x L级(L0/L1/L2)
#   [B 联网只读] WebFetch/WebSearch  : 一律 allow (只读、不改本地; plan 下也放, 联网查资料是它的天职)
#   [C 代码执行] Bash / MCP 的 exec 档 : 天花板 = divide, 永不 allow
#                 例外 "纯净只读命令"直放: 命令头 in {echo,:,[,test,export,command,pwd,ls,git status|log|diff|show}
#                 且整条命令不含任何拼接符/重定向/命令替换/换行 ( | ; & < > ` $( 回车 ) -> allow
#   [D MCP] 按 md/MCP工具分级表.md 分档:
#                 readonly -> allow | write -> ask(⚠白名单免疫不了, 每次必问) | exec -> 同C | 未登记 -> ask(保守)
#
# divide(分流): hook 不表态(exit 0 无输出) -> 落回 Claude Code 原生权限流程
#               -> 查白名单: 命中即执行 / 未命中弹窗 ask
#               -> work 的 ask 一直等人; auto 的 ask 无人应答即 deny
#   注意: divide != 放行。返回 "ask" 是"强制问"(连白名单里的也问), 比 divide 更严, 别混用。
#
# 决定表 (行=工具类, 列=画像):
#                  plan            work                       auto                        bypass
#   文件写         deny            范围内L2 allow/其余 ask     范围内L1L2 allow/L0 ask     allow
#                                                              /范围外 deny
#   B 联网只读     allow           allow                      allow                       allow
#   C 代码执行     纯净only/余deny  纯净allow/其余 divide       同 work                     allow
#   D MCP 只读     allow           allow                      allow                       allow
#   D MCP 写       deny            ask                        ask                         allow
#
# L0 且结果非 deny 时: 先自动备份(滚动10份)+打 git tag。
# Bash 直放前先自查 S 级路径 -> 命中即 deny (与 check_s_level 双保险, 不依赖多 hook 决策优先级)。
# 工作区根自动检测(脚本所在 hooks/ 的上一级); 工作区外文件一律放行(exit 0)。
# 重要: 本文件必须以 UTF-8 BOM 保存! 否则 Windows PowerShell 5.1 按 GBK 读取会崩。
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# --- 工作区根 (所有分支共用) ---
$workspaceRoot = Split-Path -Parent $PSScriptRoot

# --- 决策输出 ---
function Emit([string]$decision, [string]$reason) {
    $obj = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = $decision; permissionDecisionReason = $reason } }
    [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
    exit 0
}
# divide(分流): 不表态 -> 落回原生流程(白名单命中即跑 / 未命中 ask)。注意它不是"放行"。
function Divide { exit 0 }

# --- 画像: 从 permission_mode 推 ---
$permMode = [string]$payload.permission_mode
switch ($permMode) {
    "plan"              { $profile = "plan" }   # read 与 search 都是 plan, 分不出, 统一按 search 处理
    "default"           { $profile = "work" }
    "acceptEdits"       { $profile = "auto" }
    "auto"              { $profile = "auto" }
    "bypassPermissions" { $profile = "bypass" }
    default             { $profile = "work" }   # 缺失/未知(含 dontAsk) 兜底当 work
}

$toolName = [string]$payload.tool_name

# ============ bypass: 所有工具一律放行 (S 级读禁由 check_s_level 另管) ============
if ($profile -eq "bypass") { Emit "allow" "bypass 画像: 全放开 (S 级读禁由 check_s_level 另管)。" }

# --- S 级路径自查 (Bash 直放前用; 与 check_s_level 双保险, 不依赖多 hook 决策优先级) ---
function Test-SLevelHit([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $mf = Join-Path $workspaceRoot "md\S级清单.md"
    if (-not (Test-Path $mf)) { return $null }
    $c = Get-Content $mf -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $c) { return $null }
    $m = [regex]::Match($c, '```paths\s*\r?\n([\s\S]*?)```')
    if (-not $m.Success) { return $null }
    foreach ($line in ($m.Groups[1].Value -split "`r?`n")) {
        $p = $line.Trim()
        if ((-not $p) -or $p.StartsWith('#')) { continue }
        $rel = $p.TrimEnd('/').TrimEnd('\')
        $abs = $p
        if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $workspaceRoot $p }
        try { $abs = [System.IO.Path]::GetFullPath($abs) } catch {}
        $abs = ($abs.Replace([char]47, [char]92)).TrimEnd([char]92)
        foreach ($v in @($abs, ($abs.Replace([char]92, [char]47)), $rel, ($rel.Replace([char]47, [char]92)), ($rel.Replace([char]92, [char]47)))) {
            if ($v -and ($text -like ("*" + $v + "*"))) { return $abs }
        }
    }
    return $null
}

# ============ [B] 联网只读: WebFetch / WebSearch -> 一律 allow ============
if ($toolName -eq "WebFetch" -or $toolName -eq "WebSearch") {
    $t = [string]$payload.tool_input.url
    if (-not $t) { $t = [string]$payload.tool_input.query }
    Emit "allow" ("画像=$profile / B类 联网只读($toolName) -> allow 【" + $t + "】")
}

# ============ [D] MCP 工具: 按 md/MCP工具分级表.md 分档 ============
if ($toolName -like "mcp__*") {
    $cls = "unknown"
    $tf = Join-Path $workspaceRoot "md\MCP工具分级表.md"
    if (Test-Path $tf) {
        $tc = Get-Content $tf -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($tc) {
            foreach ($fence in @("exec", "write", "readonly")) {   # 从严到宽, 先命中先算
                $fm = [regex]::Match($tc, ('```' + $fence + '\s*\r?\n([\s\S]*?)```'))
                if (-not $fm.Success) { continue }
                foreach ($line in ($fm.Groups[1].Value -split "`r?`n")) {
                    $n = $line.Trim()
                    if ((-not $n) -or $n.StartsWith('#')) { continue }
                    if ($toolName -eq $n) { $cls = $fence; break }
                }
                if ($cls -ne "unknown") { break }
            }
        }
    }
    # 表里没有 -> 模式兜底 (顺序从严到宽, 不可颠倒)
    if ($cls -eq "unknown") {
        if     ($toolName -match 'evaluate|run_code|_exec|execute|preview_start|preview_stop') { $cls = "exec" }
        elseif ($toolName -match '_create|_update|_delete|_remove|_add_|_write|_merge|_batch|_install|_publish|_push|_upload|_submit|_click|form_input') { $cls = "write" }
        elseif ($toolName -match '_search|_get_|_list|_read|_fetch|_find|_query|navigate|snapshot|page_text|tabs_context|_status|_detect|_check|_resolve') { $cls = "readonly" }
    }
    switch ($cls) {
        "readonly" { Emit "allow" "画像=$profile / D类 MCP只读($toolName) -> allow" }
        "write" {
            if ($profile -eq "plan") { Emit "deny" "画像=plan / D类 MCP写($toolName) -> deny (只读姿态不得改外部状态)" }
            Emit "ask" "画像=$profile / D类 MCP写($toolName) -> ask (不可逆, 白名单免疫不了, 每次必问)"
        }
        "exec" {
            if ($profile -eq "plan") { Emit "deny" "画像=plan / C类 代码执行($toolName) -> deny" }
            Divide   # work/auto: 天花板=divide, 永不 allow
        }
        default {
            if ($profile -eq "plan") { Emit "deny" "画像=plan / 未登记 MCP($toolName) -> deny" }
            Emit "ask" "画像=$profile / 未登记 MCP($toolName) -> ask (未在 md/MCP工具分级表.md 登记, 保守兜底)"
        }
    }
    exit 0
}

# ============ [C] Bash: S级自查 -> 纯净只读直放 -> 否则 divide ============
if ($toolName -eq "Bash") {
    $cmd = [string]$payload.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

    $sHit = Test-SLevelHit $cmd
    if ($sHit) { Emit "deny" ("C类 Bash 触及 S 级路径 【" + $sHit + "】 -> deny (与 check_s_level 双保险)") }

    # 脏字符: 任何拼接/重定向/命令替换/换行 -> 一律不得直放 (echo x && rm -rf / 也是 echo 开头)
    $bt    = [string][char]96
    $dirty = ($cmd -like '*|*') -or ($cmd -like '*;*') -or ($cmd -like '*&*') -or
             ($cmd -like '*<*') -or ($cmd -like '*>*') -or $cmd.Contains($bt) -or
             $cmd.Contains('$(') -or ($cmd -match '[\r\n]')

    $head  = ($cmd.Trim() -split '\s+')[0]
    $pureHeads = @('echo', ':', '[', 'test', 'export', 'command', 'pwd', 'ls')
    $pure = $false
    if (-not $dirty) {
        if ($pureHeads -contains $head)                          { $pure = $true }
        elseif ($cmd -match '^\s*git\s+(status|log|diff|show)\b') { $pure = $true }
    }
    if ($pure) { Emit "allow" ("画像=$profile / C类 Bash 纯净只读命令 -> allow 【" + $head + "】") }

    if ($profile -eq "plan") { Emit "deny" "画像=plan / C类 Bash 非只读命令 -> deny (只读姿态不得执行任意代码)" }
    Divide   # work/auto: 天花板=divide -> 白名单命中即跑 / 未命中弹窗
}

# ============ 以下: 文件写类 (Edit / Write / NotebookEdit); 其余工具一律弃权 ============
if ($toolName -ne "Edit" -and $toolName -ne "Write" -and $toolName -ne "NotebookEdit") { exit 0 }

$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.path }
if (-not $filePath) { exit 0 }

# --- 目标绝对/相对路径 ---
$absPath = $filePath
if (-not [System.IO.Path]::IsPathRooted($absPath)) { $absPath = Join-Path $workspaceRoot $absPath }
$absPath = $absPath.Replace([char]47, [char]92)   # / -> \
if ($absPath -notlike "$workspaceRoot*") { exit 0 }   # 工作区外不管
$relPath  = $absPath -replace [regex]::Escape($workspaceRoot + '\'), ''
$fileName = Split-Path $relPath -Leaf

# --- 范围: 目标是否在 cwd 子树内 ---
$cwd = [string]$payload.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = $workspaceRoot }
$cwdAbs = $cwd.Replace([char]47, [char]92)
try { $cwdAbs = [System.IO.Path]::GetFullPath($cwdAbs) } catch {}
$cwdAbs = $cwdAbs.TrimEnd([char]92)
$inScope = ($absPath -ieq $cwdAbs) -or $absPath.StartsWith(($cwdAbs + [char]92), [System.StringComparison]::OrdinalIgnoreCase)

# --- L级 映射 (须与 after_edit.ps1 / 安全审核.ps1 / 权限系统.md 保持一致) ---
$L0_files = @("md\权限系统.md", ".claude\settings.json")
$L1_files = @("CLAUDE.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md\变更标记规范.md", "md\画像映射表.md", "md\S级清单.md", "md\MCP工具分级表.md")
$L1_dirs  = @(".claude\agents\", "hooks\", "Automation\")
$level = "L2"
foreach ($f in $L0_files) { if ($relPath -eq $f) { $level = "L0"; break } }
if ($level -eq "L2") { foreach ($f in $L1_files) { if ($relPath -eq $f) { $level = "L1"; break } } }
if ($level -eq "L2") { foreach ($d in $L1_dirs)  { if ($relPath.StartsWith($d)) { $level = "L1"; break } } }
if ($level -eq "L2" -and $relPath -like "*\.claude\settings.json") { $level = "L1" }   # 各子项目"钩子覆盖件"(根的 .claude\settings.json 已在 L0 优先命中)

$scopeTxt = if ($inScope) { "范围内" } else { "范围外" }

# plan(read/search): 一律 deny (plan 原生也禁写, 此为兜底; bypass 已在分流处提前放行)
if ($profile -eq "plan") { Emit "deny" "plan 画像(read/search): 只读姿态, 禁止一切写入。要写请先切到 work/auto 画像。" }

# 基础决定 (work / auto)
$decision = "ask"
if ($profile -eq "work") {
    if ($level -eq "L2") { $decision = if ($inScope) { "allow" } else { "ask" } }
    else                 { $decision = "ask" }   # L0/L1 恒 ask
}
elseif ($profile -eq "auto") {
    if (-not $inScope) { $decision = "deny" }
    else {
        switch ($level) {
            "L2" { $decision = "allow" }
            "L1" { $decision = "allow" }
            "L0" { $decision = "ask" }   # 无人应答(无头/长时间无人)即 deny; 有人即便在别忙也能确认放行。差别: work 的 L0 一直等、不自动 deny
        }
    }
}

# L0 且将放行/询问 -> 自动备份(滚动10份) + git tag
if ($level -eq "L0" -and $decision -ne "deny") {
    if (Test-Path $absPath) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupDir = Join-Path $workspaceRoot ".backups\L0"
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $safeName = $fileName -replace '[\/:*?"<>|]', '_'
        try { Copy-Item -Path $absPath -Destination (Join-Path $backupDir ($safeName + "." + $ts + ".bak")) -Force } catch {}
        try {
            Get-ChildItem -Path $backupDir -Filter ($safeName + ".*.bak") -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 |
                ForEach-Object { try { [System.IO.File]::Delete($_.FullName) } catch {} }
        } catch {}
        Push-Location $workspaceRoot
        try { git tag ("pre-L0-" + $ts + "-" + ($safeName -replace '\.', '_')) 2>$null | Out-Null } catch {} finally { Pop-Location }
    }
}

Emit $decision ("画像=$profile / $scopeTxt / $level 【$relPath】 -> $decision")

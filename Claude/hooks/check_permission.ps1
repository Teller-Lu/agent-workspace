# ============================================
# PreToolUse hook: 画像 + 范围 + L级 写权限判定
# 触发: Edit / Write / NotebookEdit 前
# 三要素:
#   画像 = payload.permission_mode
#          plan->read/search | default->work | acceptEdits/auto->auto | bypassPermissions->bypass | 其它/缺失->work(兜底)
#   范围 = 目标是否在 payload.cwd 子树内 (in-scope / out-of-scope)
#   L级  = L0(权限制度/核心配置) / L1(关键指令/脚本) / L2(普通)
# 决定:
#   read/search : 一律 deny (plan 原生也禁写, 此为兜底)
#   work        : 范围内 L2 allow / 其余 ask ; 范围外 L2 也升为 ask
#   auto        : 范围内 L2,L1 allow / L0 ask(无人应答即 deny) ; 范围外一律 deny
#   bypass      : 一律 allow (S 读禁由 check_s_level.ps1 另管)
# L0 且结果非 deny 时: 先自动备份(滚动10份)+打 git tag。
# 工作区根自动检测(脚本所在 hooks/ 的上一级); 工作区外文件一律放行(exit 0)。
# 重要: 本文件必须以 UTF-8 BOM 保存! 否则 Windows PowerShell 5.1 按 GBK 读取会崩。
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.path }
if (-not $filePath) { exit 0 }

# --- 工作区根 & 目标绝对/相对路径 ---
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$absPath = $filePath
if (-not [System.IO.Path]::IsPathRooted($absPath)) { $absPath = Join-Path $workspaceRoot $absPath }
$absPath = $absPath.Replace([char]47, [char]92)   # / -> \
if ($absPath -notlike "$workspaceRoot*") { exit 0 }   # 工作区外不管
$relPath  = $absPath -replace [regex]::Escape($workspaceRoot + '\'), ''
$fileName = Split-Path $relPath -Leaf

# --- 画像: 从 permission_mode 推 ---
$permMode = [string]$payload.permission_mode
switch ($permMode) {
    "plan"              { $profile = "read" }
    "default"           { $profile = "work" }
    "acceptEdits"       { $profile = "auto" }
    "auto"              { $profile = "auto" }
    "bypassPermissions" { $profile = "bypass" }
    default             { $profile = "work" }   # 缺失/未知(含 dontAsk) 兜底当 work
}

# --- 范围: 目标是否在 cwd 子树内 ---
$cwd = [string]$payload.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = $workspaceRoot }
$cwdAbs = $cwd.Replace([char]47, [char]92)
try { $cwdAbs = [System.IO.Path]::GetFullPath($cwdAbs) } catch {}
$cwdAbs = $cwdAbs.TrimEnd([char]92)
$inScope = ($absPath -ieq $cwdAbs) -or $absPath.StartsWith(($cwdAbs + [char]92), [System.StringComparison]::OrdinalIgnoreCase)

# --- L级 映射 (须与 after_edit.ps1 / 安全审核.ps1 / 权限系统.md 保持一致) ---
$L0_files = @("md\权限系统.md", ".claude\settings.json")
$L1_files = @("CLAUDE.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md\变更标记规范.md", "md\画像映射表.md", "md\S级清单.md")
$L1_dirs  = @(".claude\agents\", "hooks\", "Automation\")
$level = "L2"
foreach ($f in $L0_files) { if ($relPath -eq $f) { $level = "L0"; break } }
if ($level -eq "L2") { foreach ($f in $L1_files) { if ($relPath -eq $f) { $level = "L1"; break } } }
if ($level -eq "L2") { foreach ($d in $L1_dirs)  { if ($relPath.StartsWith($d)) { $level = "L1"; break } } }
if ($level -eq "L2" -and $relPath -like "*\.claude\settings.json") { $level = "L1" }   # 各子项目"钩子覆盖件"(根的 .claude\settings.json 已在 L0 优先命中)

function Emit([string]$decision, [string]$reason) {
    $obj = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = $decision; permissionDecisionReason = $reason } }
    [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
    exit 0
}

$scopeTxt = if ($inScope) { "范围内" } else { "范围外" }

# bypass: 一律放行 (S 读禁另管)
if ($profile -eq "bypass") { Emit "allow" "bypass 画像: 全放开 (S 读禁由 check_s_level 另管)。" }
# read/search (plan): 一律 deny
if ($profile -eq "read")   { Emit "deny"  "read/search 画像(plan): 只读姿态, 禁止一切写入。要写请先切到 work/auto 画像。" }

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

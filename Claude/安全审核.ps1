# ============================================
# 安全审核.ps1 — 统一权限安全员（查询 + 手动批准流 + L0 加固）
# ============================================
# 两种执行机制，同一套权限策略（L0/L1/L2，权威定义见 md/文件权限系统.md §三）：
#   1) Hook 模式（Claude Code）：hooks/check_permission.ps1 + after_edit.ps1 自动门禁/审计/提交
#   2) 手动模式（Codex 等 无 hook 的 Agent）：本脚本 -Request/-Approve/-Log 流程
# 本脚本兼顾两者：手动批准流 + 审计查询。审计 schema 与 after_edit.ps1 一致，-Report 通用。
# 工作区根目录自动检测（取本脚本所在目录）。本文件以 UTF-8 BOM 保存。
# ============================================
param(
    [switch]$Request, [switch]$Approve, [switch]$Deny, [switch]$Log,
    [switch]$Report, [int]$Last = 0, [string]$File, [string]$Level,
    [string]$Reason, [string]$Summary, [string]$Agent,
    [string]$Device, [string]$Account, [string]$Provider, [string]$Project,
    [string]$PermissionLevel, [string]$RelatedTask, [switch]$Help
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$workspaceRoot = $PSScriptRoot
if (-not $workspaceRoot) { $workspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$logPath = Join-Path $workspaceRoot "审计日志.jsonl"

# ---- 权限清单（须与 hooks/*.ps1 及 md/文件权限系统.md §三 一致）----
$L0_files = @("md\文件权限系统.md", ".claude\settings.json")
$L1_files = @("CLAUDE.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md\变更标记规范.md", "md\画像映射表.md", "md\S级清单.md")
$L1_dirs  = @(".claude\agents\", "hooks\", "Automation\")

function Get-Level($rel) {
    foreach ($f in $L0_files) { if ($rel -eq $f) { return "L0" } }
    foreach ($f in $L1_files) { if ($rel -eq $f) { return "L1" } }
    foreach ($d in $L1_dirs)  { if ($rel.StartsWith($d)) { return "L1" } }
    return "L2"
}

if ($Agent) { $agentId = $Agent } else { $agentId = "agent-${PID}-$(Get-Date -Format 'HHmmss')" }
if (-not $Device)   { $Device = $env:COMPUTERNAME }
if (-not $Device)   { $Device = "unknown" }
$usr = $env:USERNAME; if (-not $usr) { $usr = "unknown" }
if (-not $Account)  { $Account = "agent-main" }
if (-not $Provider) { $Provider = "unknown" }
if (-not $Project)  { $Project = "ROOT" }

function Resolve-Rel($f) {
    $abs = $f
    if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $workspaceRoot $abs }
    $abs = $abs -replace '/', '\'
    if ($abs -notlike "$workspaceRoot*") { return $null }
    return $abs -replace [regex]::Escape($workspaceRoot + '\'), ''
}

function Write-AuditEntry([string]$Action, [string]$TargetFile, [string]$Detail, [string]$Actor, [string]$lvl) {
    $entry = [ordered]@{
        id = "ROOT-$(Get-Date -Format 'yyyyMMdd')-MANUAL"
        ts = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        device = $Device; user = $usr; account = $Account; provider = $Provider
        project = $Project; actor = $Actor; subagent = $null
        action = $Action; file = $TargetFile; level = $lvl
        summary = $Detail; commit = ""; related_task = $(if ($RelatedTask) { $RelatedTask } else { "ROOT-$(Get-Date -Format 'yyyyMMdd')-MANUAL" })
    }
    Add-Content -Path $logPath -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    Write-Host "[安全员] $($entry.ts) | $Action | $TargetFile | $Actor"
}

function L0-Harden($rel) {
    $abs = Join-Path $workspaceRoot $rel
    if (-not (Test-Path $abs)) { return }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = Join-Path $workspaceRoot ".backups\L0"
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $safeName = (Split-Path $rel -Leaf) -replace '[\/:*?"<>|]', '_'
    try { Copy-Item -Path $abs -Destination (Join-Path $backupDir ($safeName + "." + $ts + ".bak")) -Force } catch {}
    try {
        Get-ChildItem -Path $backupDir -Filter ($safeName + ".*.bak") -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
    Push-Location $workspaceRoot
    try { git tag ("pre-L0-" + $ts + "-" + ($safeName -replace '\.', '_')) 2>$null | Out-Null } catch {} finally { Pop-Location }
    Write-Host "[安全员] L0 加固：已备份 + 打 git tag pre-L0-$ts-$safeName"
}

# ---- 帮助 ----
if ($Help -or (-not $Request -and -not $Approve -and -not $Deny -and -not $Log -and -not $Report -and $Last -eq 0 -and $File -eq "" -and $Level -eq "")) {
    Write-Host @"
安全审核.ps1 — 统一权限安全员（查询 + 手动批准流 + L0 加固）

【手动批准流】（无 hook 的 Agent 用；hook 模式由 hooks/*.ps1 自动完成）
  -Request -File "路径" [-Reason "原因"] [-Agent "..."]   提交修改申请（L0 自动备份+打 tag）
  -Approve -File "路径"                                   人工批准
  -Deny    -File "路径"                                   人工拒绝
  -Log     -File "路径" -Summary "摘要" [-Agent "..."]    记录修改完成

【查询】
  -Report                              全部审计记录
  -Last <N>                            最近 N 条
  -File  <文件名>                      过滤某文件
  -Level <L0|L1|L2>                    过滤某级别

可选上下文：-Device -Account -Provider -Project -PermissionLevel -RelatedTask
批准指令：yes/同意/是  拒绝指令：no/拒绝/否
"@
    exit 0
}

# ---- 手动批准流 ----
if ($Request) {
    if (-not $File) { Write-Host "用法: -Request -File `"路径`" [-Reason `"原因`"]"; exit 1 }
    $rel = Resolve-Rel $File; if (-not $rel) { $rel = $File }
    $lvl = if ($PermissionLevel) { $PermissionLevel } else { Get-Level $rel }
    if ($lvl -eq "L0") { L0-Harden $rel }
    Write-AuditEntry -Action "REQUEST" -TargetFile $rel -Detail $Reason -Actor $agentId -lvl $lvl
    Write-Host "申请已记录（$lvl）。待用户 -Approve 后再修改。"; exit 0
}
if ($Approve) {
    if (-not $File) { Write-Host "用法: -Approve -File `"路径`""; exit 1 }
    $rel = Resolve-Rel $File; if (-not $rel) { $rel = $File }
    $lvl = if ($PermissionLevel) { $PermissionLevel } else { Get-Level $rel }
    Write-AuditEntry -Action "APPROVE" -TargetFile $rel -Detail "人工批准" -Actor "Human" -lvl $lvl
    Write-Host "批准已记录。"; exit 0
}
if ($Deny) {
    if (-not $File) { Write-Host "用法: -Deny -File `"路径`""; exit 1 }
    $rel = Resolve-Rel $File; if (-not $rel) { $rel = $File }
    Write-AuditEntry -Action "DENY" -TargetFile $rel -Detail "人工拒绝" -Actor "Human" -lvl (Get-Level $rel)
    Write-Host "拒绝已记录。"; exit 0
}
if ($Log) {
    if (-not $File) { Write-Host "用法: -Log -File `"路径`" -Summary `"摘要`""; exit 1 }
    $rel = Resolve-Rel $File; if (-not $rel) { $rel = $File }
    $lvl = if ($PermissionLevel) { $PermissionLevel } else { Get-Level $rel }
    Write-AuditEntry -Action "MODIFY" -TargetFile $rel -Detail $Summary -Actor $agentId -lvl $lvl
    Write-Host "修改已记录。"; exit 0
}

# ---- 查询 ----
if (-not (Test-Path $logPath)) {
    Write-Host "审计日志不存在：$logPath（首次修改文件后由 hook 或本脚本自动创建）"; exit 0
}
$entries = @()
Get-Content -Path $logPath -Encoding UTF8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
        $e = $_ | ConvertFrom-Json
        if ($File -ne "" -and $e.file -notlike "*$File*") { return }
        if ($Level -ne "" -and $e.level -ne $Level) { return }
        $entries += $e
    } catch {}
}
if ($Last -gt 0 -and $entries.Count -gt $Last) { $entries = $entries[-$Last..-1] }
if ($entries.Count -eq 0) { Write-Host "无匹配的审计记录。"; exit 0 }
Write-Host ("共 {0} 条审计记录:" -f $entries.Count)
Write-Host ("-" * 80)
foreach ($e in $entries) {
    Write-Host ("[{0}] {1} {2} | {3} | {4}" -f $e.id, $e.ts, $e.level, $e.action, $e.file)
    if ($e.summary) { Write-Host ("    -> {0}" -f $e.summary) }
}
exit 0
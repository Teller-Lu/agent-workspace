# ============================================
# PostToolUse hook: 写审计 + git commit
# 触发: Edit / Write / NotebookEdit 完成后
# 行为:
#   1. 追加一条 JSON 到 审计日志.jsonl
#   2. git add <文件> && git commit
# 工作区根目录自动检测。审计字段中的 device/account 用环境变量推断, 通用不硬编码。
# 注意: 不应 fail 整个工具调用: 用 try/catch + exit 0
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# 读取 stdin
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try {
    $payload = $raw | ConvertFrom-Json
} catch {
    Write-Error "after_edit.ps1: 无法解析输入 JSON"
    exit 0
}

$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.path }
if (-not $filePath) { exit 0 }

# 自动检测工作区根目录
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$absPath = $filePath
if (-not [System.IO.Path]::IsPathRooted($absPath)) {
    $absPath = Join-Path $workspaceRoot $absPath
}
$absPath = $absPath -replace '/', '\'
$relPath = $absPath -replace [regex]::Escape($workspaceRoot + '\'), ''

# 只对工作区内的文件做审计
if ($absPath -notlike "$workspaceRoot*") { exit 0 }

# 跳过 .git/ 和 .backups/ 内部文件
if ($relPath -like ".git\*" -or $relPath -like ".backups\*") { exit 0 }

# ============================================
# 推断级别（与 check_permission.ps1 保持一致）
# ============================================
$L0_files = @("md\权限系统.md", ".claude\settings.json")
$L1_files = @("CLAUDE.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md\变更标记规范.md", "md\画像映射表.md", "md\S级清单.md", "md\MCP工具分级表.md")
$L1_dirs = @(".claude\agents\", "hooks\", "Automation\")

$level = "L2"
foreach ($f in $L0_files) { if ($relPath -eq $f) { $level = "L0"; break } }
if ($level -eq "L2") {
    foreach ($f in $L1_files) { if ($relPath -eq $f) { $level = "L1"; break } }
}
if ($level -eq "L2") {
    foreach ($d in $L1_dirs) { if ($relPath.StartsWith($d)) { $level = "L1"; break } }
}
if ($level -eq "L2" -and $relPath -like "*\.claude\settings.json") { $level = "L1" }   # 各子项目"钩子覆盖件"(根的 .claude\settings.json 已在 L0 优先命中)

# ============================================
# 收集环境上下文 (通用: 不预设特定终端名)
# ============================================
$device   = $env:COMPUTERNAME
if (-not $device) { $device = "unknown" }
$user     = $env:USERNAME
if (-not $user) { $user = "unknown" }
$account  = "agent-main"
$provider = "unknown"

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
# 审计 ID: 暂用日期, AI 可在提交前 update
$auditId = "ROOT-$(Get-Date -Format 'yyyyMMdd')-AUTO"

# ============================================
# 1. 追加 JSON 到 审计日志.jsonl
# ============================================
$logPath = Join-Path $workspaceRoot "审计日志.jsonl"
$entry = [ordered]@{
    id            = $auditId
    ts            = $timestamp
    device        = $device
    user          = $user
    account       = $account
    provider      = $provider
    project       = "ROOT"
    actor         = "系统Agent"
    subagent      = $null
    action        = $toolName
    file          = $relPath
    level         = $level
    summary       = "$toolName on $relPath"
    commit        = ""
    related_task  = $auditId
}

try {
    $jsonLine = ($entry | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path $logPath -Value $jsonLine -Encoding UTF8
} catch {
    Write-Error "写入 审计日志.jsonl 失败: $($_.Exception.Message)"
}

# ============================================
# 2. git add + git commit（仅在仓库有 commit 历史时）
# ============================================
Push-Location $workspaceRoot
try {
    $hasCommits = $false
    try {
        $null = git rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $hasCommits = $true }
    } catch {}

    if ($hasCommits) {
        git add $relPath 审计日志.jsonl 2>&1 | Out-Null

        $staged = git diff --cached --name-only
        if ($staged) {
            $msg = "[$auditId] $level $toolName`: $relPath"
            git commit -m $msg 2>&1 | Out-Null

            # 把 commit hash 回写到审计日志最后一行
            $commitHash = (git rev-parse --short HEAD 2>$null)
            if ($commitHash -and (Test-Path $logPath)) {
                $lines = Get-Content $logPath -Encoding UTF8
                if ($lines.Count -gt 0) {
                    $lastLine = $lines[-1]
                    try {
                        $lastEntry = $lastLine | ConvertFrom-Json
                        $lastEntry.commit = $commitHash
                        $lines[-1] = ($lastEntry | ConvertTo-Json -Compress -Depth 5)
                        Set-Content -Path $logPath -Value $lines -Encoding UTF8
                    } catch {}
                }
            }
        }
    }
} catch {
    Write-Error "git commit 失败: $($_.Exception.Message)"
} finally {
    Pop-Location
}

exit 0
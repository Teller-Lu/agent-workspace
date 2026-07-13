# ============================================
# Stop hook: 回合结束时追加审计日志
# 触发: Codex 回合结束（Stop 事件）
# 行为: 追加一条 JSON 到 审计日志.jsonl（记录回合结束时间）
# 工作区根目录自动检测（脚本在 hooks/ 下，上一级是工作区根）
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $workspaceRoot "审计日志.jsonl"

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
$device = $env:COMPUTERNAME
if (-not $device) { $device = "unknown" }
$user = $env:USERNAME
if (-not $user) { $user = "unknown" }

$entry = [ordered]@{
    id       = "TURN-$(Get-Date -Format 'yyyyMMddHHmmss')"
    ts       = $timestamp
    device   = $device
    user     = $user
    action   = "turn-end"
    file     = ""
    level    = ""
    summary  = "Codex 回合结束"
    commit   = ""
}

try {
    $jsonLine = ($entry | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path $logPath -Value $jsonLine -Encoding UTF8
} catch {
    Write-Error "写入审计日志失败: $($_.Exception.Message)"
}

exit 0
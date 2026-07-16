# ============================================
# Stop hook: 回合结束 → 审计 + 自动提交
# 彻底重写版：解决 git 不在 PATH / 文件未刷新 / 静默失败问题
# 关键改进：
#   1. 用 git.exe 全路径，不依赖 PATH
#   2. 等 500ms 让磁盘写入刷新
#   3. 所有操作写调试日志到 hooks/.after_turn_debug.log
#   4. git add -u + git commit --no-verify
# 本文件必须以 UTF-8 BOM 保存!（PS 5.1 兼容）
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $workspaceRoot "审计日志.jsonl"
$debugLogPath = Join-Path $PSScriptRoot ".after_turn_debug.log"

# --- helper: 写调试日志 ---
function Write-DebugLog($msg) {
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        Add-Content -Path $debugLogPath -Value "[$ts] $msg" -Encoding UTF8
    } catch {}
}

# --- helper: 找 git.exe 全路径 ---
function Get-GitExe {
    # 1. Get-Command git
    try {
        $cmd = Get-Command git -ErrorAction Stop
        if ($cmd) { return $cmd.Source }
    } catch {}
    # 2. 常见路径
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$gitExe = Get-GitExe
Write-DebugLog "=== after_turn START ==="
Write-DebugLog "workspaceRoot=$workspaceRoot"
Write-DebugLog "gitExe=$gitExe"

if (-not $gitExe) {
    Write-DebugLog "ERROR: git.exe not found, aborting"
    exit 0
}

# 等 500ms 让文件写入刷新到磁盘
Start-Sleep -Milliseconds 500

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
$device = $env:COMPUTERNAME
if (-not $device) { $device = "unknown" }
$user = $env:USERNAME
if (-not $user) { $user = "unknown" }

# --- 1. 回合结束审计 ---
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
    Write-DebugLog "audit entry written OK"
} catch {
    Write-DebugLog "audit entry FAILED: $($_.Exception.Message)"
}

# --- 2. 检测并恢复被删除的 tracked 文件 ---
try {
    $gitStatusRaw = & $gitExe -C $workspaceRoot status --porcelain 2>&1
    Write-DebugLog "git status raw: $gitStatusRaw"
    
    if ($gitStatusRaw) {
        $deletedFiles = @()
        foreach ($line in $gitStatusRaw) {
            $lineStr = "$line"
            if ($lineStr -match "^ D " -or $lineStr -match "^D  " -or $lineStr -match "^ D  ") {
                $file = $lineStr.Substring(3).Trim()
                $deletedFiles += $file
                Write-DebugLog "deleted file detected: $file"
            }
        }

        if ($deletedFiles.Count -gt 0) {
            $L0_FILES = @("md/文件权限系统.md", ".codex/config.toml", ".codex/hooks.json", "md/config.toml.模板", "md/hooks.json.模板")
            $L1_FILES = @("AGENTS.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md/画像映射表.md", "md/变更标记规范.md", "md/S级清单.md")

            foreach ($file in $deletedFiles) {
                $level = "L2"
                if ($L0_FILES -contains $file) { $level = "L0" }
                elseif ($L1_FILES -contains $file) { $level = "L1" }
                elseif ($file -match "^(hooks/|git-hooks/|Automation/|md/)") { $level = "L1" }

                $delEntry = [ordered]@{
                    id       = "DELETE-$(Get-Date -Format 'yyyyMMddHHmmss')-$($file -replace '[^a-zA-Z0-9]', '')"
                    ts       = $timestamp
                    device   = $device
                    user     = $user
                    action   = "file-deleted-detected"
                    file     = $file
                    level    = $level
                    summary  = "检测到 tracked 文件被删除"
                    commit   = ""
                }
                try {
                    $delJson = ($delEntry | ConvertTo-Json -Compress -Depth 5)
                    Add-Content -Path $logPath -Value $delJson -Encoding UTF8
                } catch {}

                $restoreResult = & $gitExe -C $workspaceRoot checkout -- $file 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-DebugLog "restored: $file"
                    $restoreEntry = [ordered]@{
                        id       = "RESTORE-$(Get-Date -Format 'yyyyMMddHHmmss')-$($file -replace '[^a-zA-Z0-9]', '')"
                        ts       = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
                        device   = $device
                        user     = $user
                        action   = "file-restored"
                        file     = $file
                        level    = $level
                        summary  = "自动恢复被删除的文件"
                        commit   = ""
                    }
                    try {
                        $restoreJson = ($restoreEntry | ConvertTo-Json -Compress -Depth 5)
                        Add-Content -Path $logPath -Value $restoreJson -Encoding UTF8
                    } catch {}
                    [Console]::Error.WriteLine("[after_turn] WARNING: [$file] 被删除，已从 git 恢复。")
                } else {
                    Write-DebugLog "restore FAILED: $file -> $restoreResult"
                }
            }
        }
    }
} catch {
    Write-DebugLog "delete detection error: $($_.Exception.Message)"
}

# --- 3. 自动提交文件变更 ---
try {
    $gitStatusForCommit = & $gitExe -C $workspaceRoot status --porcelain 2>&1
    Write-DebugLog "git status for commit: $gitStatusForCommit"
    
    $hasChangesToCommit = $false
    $changedFiles = @()
    if ($gitStatusForCommit) {
        foreach ($line in $gitStatusForCommit) {
            $lineStr = "$line"
            Write-DebugLog "checking line: [$lineStr]"
            # 排除 D（删除，已由上面处理）和 ??（未跟踪，需手动 add）
            if ($lineStr -notmatch "^ D " -and $lineStr -notmatch "^D  " -and $lineStr -notmatch "^\?\?" -and $lineStr.Trim() -ne "") {
                $hasChangesToCommit = $true
                $changedFiles += $lineStr
            }
        }
    }

    Write-DebugLog "hasChangesToCommit=$hasChangesToCommit changedFiles=$($changedFiles -join '; ')"

    if ($hasChangesToCommit) {
        Write-DebugLog "running git add -u..."
        $addResult = & $gitExe -C $workspaceRoot add -u 2>&1
        Write-DebugLog "git add result: $addResult (rc=$LASTEXITCODE)"

        Write-DebugLog "running git commit --no-verify..."
        $commitResult = & $gitExe -C $workspaceRoot commit --no-verify -m "auto: turn-end auto-commit" 2>&1
        $commitRc = $LASTEXITCODE
        Write-DebugLog "git commit result: $commitResult (rc=$commitRc)"

        if ($commitRc -eq 0) {
            $commitHash = & $gitExe -C $workspaceRoot rev-parse --short HEAD 2>&1
            $commitHashStr = "$commitHash"
            Write-DebugLog "commit OK, hash=$commitHashStr"

            $autoEntry = [ordered]@{
                id       = "AUTO-COMMIT-$(Get-Date -Format 'yyyyMMddHHmmss')"
                ts       = $timestamp
                device   = $device
                user     = $user
                action   = "auto-commit"
                file     = ""
                level    = ""
                summary  = "回合结束自动提交文件变更"
                commit   = $commitHashStr
            }
            try {
                $autoJson = ($autoEntry | ConvertTo-Json -Compress -Depth 5)
                Add-Content -Path $logPath -Value $autoJson -Encoding UTF8
            } catch {}
        } else {
            Write-DebugLog "commit FAILED rc=$commitRc"
            [Console]::Error.WriteLine("[after_turn] auto-commit FAILED: $commitResult")
        }
    } else {
        Write-DebugLog "no changes to commit"
    }
} catch {
    Write-DebugLog "auto-commit error: $($_.Exception.Message)"
}

Write-DebugLog "=== after_turn END ==="
exit 0

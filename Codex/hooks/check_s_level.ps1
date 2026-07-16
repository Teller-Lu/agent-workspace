# ============================================
# PreToolUse hook: S 级读取拦截 + L0/L1 删除拦截 + 外部写入拦截
# 匹配: Bash（Codex 唯一能匹配的工具）
# 行为:
#   1. 命令触及对方 AI 的 S 级路径 -> deny（硬拦）
#   2. 命令删除 L0 文件 -> deny（硬拦，需双确认）
#   3. 命令删除 L1 文件 -> ask（请求批准）
#   4. 命令写入/删除工作区外的路径 -> ask（请求批准）
#   5. 其他 -> 放行
# S 级路径从 md/S级清单.md 的 paths 代码块读取（用 IndexOf 而非正则）
# 重要: 本文件必须以 UTF-8 BOM 保存!（PS 5.1 兼容）
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolName = $payload.tool_name
$command  = $null
$filePath = $null

if ($toolName -eq "Bash" -or $toolName -eq "shell_command") {
    $command = $payload.tool_input.command
    if (-not $command) { exit 0 }
} else {
    $filePath = $payload.tool_input.file_path
    if (-not $filePath) { $filePath = $payload.tool_input.path }
    if (-not $filePath) { exit 0 }
    $command = $filePath
}

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$target = if ($command) { $command } else { $filePath }

# ============================================
# 1. S 级读取拦截
# ============================================
$sManifestPath = Join-Path $workspaceRoot "md\S级清单.md"
if (Test-Path $sManifestPath) {
    $manifestContent = [System.IO.File]::ReadAllText($sManifestPath, [System.Text.Encoding]::UTF8)
    if ($manifestContent) {
        # 用 IndexOf 查找 paths 围栏（避免正则转义问题）
        $fence = [string]::new([char]96, 3)
        $fenceLabel = "`n" + $fence + "paths"
        $startIdx = $manifestContent.IndexOf($fenceLabel)
            if ($startIdx -ge 0) { $startIdx++ }
        if ($startIdx -ge 0) {
            $lineStart = $manifestContent.IndexOf("`n", $startIdx)
            if ($lineStart -ge 0) { $lineStart++ }
            $endIdx = $manifestContent.IndexOf($fence, $lineStart)
            if ($endIdx -gt $lineStart) {
                $pathsBlock = $manifestContent.Substring($lineStart, $endIdx - $lineStart)
                $sPaths = $pathsBlock -split "`r?`n" | ForEach-Object {
                    $line = $_.Trim()
                    if ($line -and $line -notmatch "^#") { $line }
                }

                if ($sPaths -and $sPaths.Count -gt 0) {
                    $sPathPairs = @()
                    foreach ($sp in $sPaths) {
                        $relPath = $sp.TrimEnd("/").TrimEnd("\")
                        $absPath = $sp
                        if (-not [System.IO.Path]::IsPathRooted($absPath)) {
                            $absPath = Join-Path $workspaceRoot $sp
                        }
                        $absPath = [System.IO.Path]::GetFullPath($absPath)
                        $absPath = $absPath -replace "/", "\"
                        $absPath = $absPath.TrimEnd("\")
                        $sPathPairs += @{ Rel = $relPath; Abs = $absPath }
                    }

                    foreach ($pair in $sPathPairs) {
                        $variants = @(
                            $pair.Abs,
                            ($pair.Abs -replace "\\", "/"),
                            ($pair.Abs -replace "\\", "\\"),
                            $pair.Rel,
                            ($pair.Rel -replace "/", "\"),
                            ($pair.Rel -replace "\\", "/")
                        )
                        foreach ($variant in $variants) {
                            if ($variant -and $target -like "*$variant*") {
                                $obj = @{
                                    hookSpecificOutput = @{
                                        hookEventName            = "PreToolUse"
                                        permissionDecision       = "deny"
                                        permissionDecisionReason = "S 级（秘密）文件/目录 [$($pair.Abs)] 不可被其他 AI 读取。自动拦截。"
                                    }
                                }
                                [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
                                exit 0
                            }
                        }
                    }
                }
            }
        }
    }
}

# ============================================
# 2. L0/L1 删除拦截
# ============================================
$L0_FILES = @("md/文件权限系统.md", ".codex/config.toml", ".codex/hooks.json", "md/config.toml.模板", "md/hooks.json.模板")
$L1_FILES = @("AGENTS.md", ".gitignore", "安全审核.ps1", "审计日志.jsonl", "md/画像映射表.md", "md/变更标记规范.md", "md/S级清单.md")

$deletePatterns = @("rm ", "rm -", "rmdir", "del ", "erase ", "Remove-Item", "ri ", "rd ", "os.remove", "os.unlink", "shutil.rmtree", "git rm")
$isDelete = $false
foreach ($dp in $deletePatterns) {
    if ($target -like "*$dp*") { $isDelete = $true; break }
}

if ($isDelete) {
    foreach ($f in $L0_FILES) {
        if ($target -like "*$f*") {
            $obj = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "deny"; permissionDecisionReason = "L0 文件 [$f] 的删除需双确认。未经批准的删除已被拦截。" } }
            [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
            exit 0
        }
    }
    foreach ($f in $L1_FILES) {
        if ($target -like "*$f*") {
            $obj = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "ask"; permissionDecisionReason = "L1 文件 [$f] 的删除需审批。" } }
            [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
            exit 0
        }
    }
}

# ============================================
# 3. 外部写入/删除拦截
# ============================================
$winPaths = [regex]::Matches($target, '[A-Za-z]:\\[^\s"''|*?<>]+')
$winFwdPaths = [regex]::Matches($target, '[A-Za-z]:/[^\s"''|*?<>]+')
$unixPaths = [regex]::Matches($target, '/[a-z]/[^\s"''|*?<>]+')
$allPaths = @()
foreach ($m in $winPaths) { $allPaths += $m.Value }
foreach ($m in $winFwdPaths) { $allPaths += $m.Value }
foreach ($m in $unixPaths) { $allPaths += $m.Value }

$wsVariants = @($workspaceRoot, ($workspaceRoot -replace "\\", "/"))
$systemPaths = @("C:\Windows", "C:\Users", "C:\Program", "C:\tmp", "/c/Windows", "/c/Users", "/c/Program", "/tmp", "/c/tmp")

foreach ($path in $allPaths) {
    $isExternal = $true
    $isSystem = $false
    foreach ($sp in $systemPaths) {
        if ($path -like "*$sp*") { $isSystem = $true; break }
    }
    if ($isSystem) { continue }
    foreach ($wsv in $wsVariants) {
        if ($path -like "*$wsv*") { $isExternal = $false; break }
    }
    if ($isExternal) {
        $readPatterns = @("Get-Content", "cat ", "type ", "Test-Path", "Get-Item", "Select-String", "grep", "findstr", "head ", "tail ", "more ")
        $isRead = $false
        foreach ($rp in $readPatterns) {
            if ($target -like "*$rp*") { $isRead = $true; break }
        }
        if (-not $isRead) {
            $obj = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "ask"; permissionDecisionReason = "命令涉及工作区外的文件操作。需审批。" } }
            [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
            exit 0
        }
    }
}

exit 0

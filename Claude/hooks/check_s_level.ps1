# ============================================
# PreToolUse hook: S 级文件读取拦截
# 匹配: Read（Claude）+ Bash/shell_command（Claude + Codex）
# 行为: 命令/路径触及 S 级目录 → deny（硬拦，无需人工）
# S 级路径从 md/S级清单.md 的 ```paths 代码块读取
# 重要: 本文件必须以 UTF-8 BOM 保存!（PS 5.1 兼容）
# ============================================

$ErrorActionPreference = "Continue"
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# 提取目标：命令字符串或文件路径
$toolName = $payload.tool_name
$command  = $null
$filePath = $null

if ($toolName -eq "Bash" -or $toolName -eq "shell_command") {
    $command = $payload.tool_input.command
    if (-not $command) { exit 0 }
} else {
    # Read / Edit / Write / NotebookEdit 等
    $filePath = $payload.tool_input.file_path
    if (-not $filePath) { $filePath = $payload.tool_input.path }
    if (-not $filePath) { exit 0 }
}

# 自动检测工作区根目录（脚本在 hooks/ 下，上一级是工作区根）
$workspaceRoot = Split-Path -Parent $PSScriptRoot

# 读取 S 级清单
$sManifestPath = Join-Path $workspaceRoot "md\S级清单.md"
if (-not (Test-Path $sManifestPath)) { exit 0 }

$manifestContent = Get-Content $sManifestPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if (-not $manifestContent) { exit 0 }

# 从 ```paths 代码块提取路径（每行一个，# 开头为注释）
$pathsMatch = [regex]::Match($manifestContent, '```paths\s*\r?\n([\s\S]*?)```')
if (-not $pathsMatch.Success) {
    # 自检：清单里有 paths 围栏却没匹配上 → 多半正则/围栏反引号数不一致 → 告警而非静默失效
    if ($manifestContent.Contains('```paths')) {
        [Console]::Error.WriteLine('[check_s_level] WARNING: S级清单.md 有 paths 围栏但正则未匹配到，S 防护可能失效，请检查 check_s_level.ps1 的 paths 正则反引号数。')
    }
    exit 0
}

$sPaths = $pathsMatch.Groups[1].Value -split "`r?`n" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^#') { $line }
}

if (-not $sPaths -or $sPaths.Count -eq 0) { exit 0 }

# 将 S 级路径归一化为绝对路径
$sPathsAbs = @()
foreach ($p in $sPaths) {
    $absPath = $p
    if (-not [System.IO.Path]::IsPathRooted($absPath)) {
        $absPath = Join-Path $workspaceRoot $p
    }
    $absPath = [System.IO.Path]::GetFullPath($absPath)
    $absPath = $absPath -replace '/', '\'
    $absPath = $absPath.TrimEnd('\')
    $sPathsAbs += $absPath
}

# 检查目标是否包含任何 S 级路径
$target = if ($command) { $command } else { $filePath }

foreach ($sPath in $sPathsAbs) {
    # 生成路径的多种表示形式（正斜杠/反斜杠/双反斜杠）
    $variants = @(
        $sPath,
        ($sPath -replace '\\', '/'),
        ($sPath -replace '\\', '\\')
    )
    foreach ($variant in $variants) {
        if ($target -like "*$variant*") {
            $obj = @{
                hookSpecificOutput = @{
                    hookEventName            = "PreToolUse"
                    permissionDecision       = "deny"
                    permissionDecisionReason = "S 级（秘密）文件/目录 [$sPath] 不可被其他 AI 读取。自动拦截，无需人工批准。"
                }
            }
            [Console]::Out.Write(($obj | ConvertTo-Json -Compress -Depth 5))
            exit 0
        }
    }
}

# 不是 S 级路径 → 放行
exit 0
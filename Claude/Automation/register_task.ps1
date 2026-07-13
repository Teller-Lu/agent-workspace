# register_task.ps1 — 一次性注册每日定时任务（Windows 任务计划程序）
# 任务名：AgentWorkspace_Daily，每日 22:00 触发 Automation/daily_run.sh（经 Git Bash）
# 卸载：Unregister-ScheduledTask -TaskName "AgentWorkspace_Daily" -Confirm:$false
# 本文件以 UTF-8 BOM 保存。
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$wsRoot = Split-Path -Parent $here
$bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
if (-not $bash) {
    Write-Host "未找到 bash（需要 Git Bash）。请先安装 Git for Windows。" -ForegroundColor Red
    exit 1
}
$action = New-ScheduledTaskAction -Execute $bash -Argument "'$here/daily_run.sh'" -WorkingDirectory $wsRoot
$trigger = New-ScheduledTaskTrigger -Daily -At 22:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "agent-workspace 每日自动化：文件变更记录 + 待办聚合 + 工作总结"
Register-ScheduledTask -TaskName "AgentWorkspace_Daily" -InputObject $task -Force | Out-Null
Write-Host "已注册定时任务 AgentWorkspace_Daily（每日 22:00）。" -ForegroundColor Green
Write-Host "卸载：Unregister-ScheduledTask -TaskName 'AgentWorkspace_Daily' -Confirm:`$false"
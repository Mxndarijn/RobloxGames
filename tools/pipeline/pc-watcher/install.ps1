# Registers the PC watcher as a per-user Scheduled Task that starts at logon (Studio needs the
# interactive desktop). Usage:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Uninstall]
param([switch]$Uninstall)

$TaskName = "StealASlime-PCWatcher"
$Root = "C:\gate\pc-watcher"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed $TaskName"
    exit 0
}

$Pythonw = (Get-Command pythonw -ErrorAction Stop).Source
$Script = Join-Path $PSScriptRoot "watcher.py"
New-Item -ItemType Directory -Force -Path (Join-Path $Root "logs") | Out-Null

$Action = New-ScheduledTaskAction -Execute $Pythonw -Argument "`"$Script`" loop" -WorkingDirectory $PSScriptRoot
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal `
    -Settings $Settings -Force | Out-Null
Write-Host "Registered $TaskName ($Pythonw $Script loop). Start now: Start-ScheduledTask -TaskName $TaskName"

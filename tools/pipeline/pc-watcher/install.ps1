# Installs the PC watcher and registers it as a per-user Scheduled Task that starts at logon
# (Studio needs the interactive desktop, so it runs as you, interactive, not elevated).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-WatcherHome C:\gate\pc-watcher] [-NoStart]
#
# The watcher checks the repo clone out at every sha it tests, so it must not run from that clone:
# this script copies watcher.py, its modules, luau\ and shots.json to <Home>\app and the task runs
# that copy. Re-run install.ps1 to update the app. Remove with uninstall.ps1.
param(
    [string]$WatcherHome = "C:\gate\pc-watcher",
    [string]$RepoUrl = "https://github.com/Mxndarijn/RobloxGames.git",
    [switch]$NoStart
)
$ErrorActionPreference = "Stop"
$TaskName = "StealASlime-PCWatcher"

foreach ($d in "app", "app\luau", "bin", "builds", "out", "logs", "state") {
    New-Item -ItemType Directory -Force -Path (Join-Path $WatcherHome $d) | Out-Null
}

# App copy (from wherever this script lives: a checkout of tools/pipeline/pc-watcher).
$App = Join-Path $WatcherHome "app"
Copy-Item -Force (Join-Path $PSScriptRoot "*.py") $App
Copy-Item -Force (Join-Path $PSScriptRoot "shots.json") $App
Copy-Item -Force (Join-Path $PSScriptRoot "luau\*.luau") (Join-Path $App "luau")

# Repo clone the watcher builds from (uses your existing git credential manager login).
$Repo = Join-Path $WatcherHome "repo"
if (-not (Test-Path (Join-Path $Repo ".git"))) {
    git clone $RepoUrl $Repo
    if ($LASTEXITCODE -ne 0) { throw "git clone $RepoUrl failed" }
}

if (-not (Test-Path (Join-Path $WatcherHome "bin\rojo.exe"))) {
    Write-Warning "bin\rojo.exe missing: put rojo 7.7.1 there (or on PATH) before the first run"
}

$Pythonw = (Get-Command pythonw -ErrorAction SilentlyContinue).Source
if (-not $Pythonw) { throw "pythonw not found (install Python 3.13 or enable its App Execution Alias)" }
$Python = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($Python) {
    & $Python (Join-Path $App "selftest.py") | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) { throw "selftest failed; not registering the task" }
}

$Script = Join-Path $App "watcher.py"
$Action = New-ScheduledTaskAction -Execute $Pythonw -Argument "`"$Script`" --home `"$WatcherHome`" loop" -WorkingDirectory $App
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal `
    -Settings $Settings -Force | Out-Null
Write-Host "Registered $TaskName : $Pythonw `"$Script`" --home `"$WatcherHome`" loop"

if (-not $NoStart) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Started. Log: $(Join-Path $WatcherHome 'logs\watcher.log')"
}

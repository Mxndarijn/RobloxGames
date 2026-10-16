# Stops and removes the PC watcher Scheduled Task. Leaves <Home> (repo, builds, reports, logs) alone.
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1 [-WatcherHome C:\gate\pc-watcher]
param([string]$WatcherHome = "C:\gate\pc-watcher")
$TaskName = "StealASlime-PCWatcher"

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
# A loop started by hand or a run in progress: their lock files hold the pid.
foreach ($lock in "loop.lock", "run.lock") {
    $f = Join-Path $WatcherHome "state\$lock"
    if (Test-Path $f) {
        $info = Get-Content $f -Raw | ConvertFrom-Json
        Stop-Process -Id $info.pid -Force -ErrorAction SilentlyContinue
        Remove-Item $f -Force
    }
}
Write-Host "Removed $TaskName (Studio windows the watcher started are killed on its next run, or close them by hand)"

param(
    [string]$Branch = 'main',
    [int]$DebounceSeconds = 5
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    $fallbackGit = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path $fallbackGit) {
        $env:Path = "C:\Program Files\Git\cmd;$env:Path"
        $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    }
}

if (-not $gitCommand) {
    Write-Error "Git is not installed or not available in PATH. Install Git, then run this script again."
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repoRoot
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, CreationTime'

$global:pendingPush = $false
$global:lastChangeAt = Get-Date

$triggerPush = {
    param($source, $eventArgs)

    $fullPath = $eventArgs.FullPath
    if ($fullPath -like "*\.git\*") {
        return
    }

    $global:pendingPush = $true
    $global:lastChangeAt = Get-Date
    Write-Host "Change detected: $($eventArgs.ChangeType) $fullPath"
}

$handlers = @(
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $triggerPush
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $triggerPush
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $triggerPush
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $triggerPush
)

Write-Host "Watching $repoRoot for changes. Auto-pushing to '$Branch' after $DebounceSeconds seconds of inactivity."
Write-Host "Press Ctrl+C to stop."

try {
    while ($true) {
        Start-Sleep -Seconds 1

        if (-not $global:pendingPush) {
            continue
        }

        $secondsSinceChange = ((Get-Date) - $global:lastChangeAt).TotalSeconds
        if ($secondsSinceChange -lt $DebounceSeconds) {
            continue
        }

        $global:pendingPush = $false

        $status = & git status --porcelain
        if (-not $status) {
            continue
        }

        Write-Host "Preparing commit and push..."
        & git add -A

        & git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            continue
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        & git commit -m "Auto update $timestamp"
        & git push origin $Branch

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Push complete at $timestamp"
        } else {
            Write-Warning "Push failed. The script will keep watching for the next change."
        }
    }
}
finally {
    foreach ($handler in $handlers) {
        Unregister-Event -SourceIdentifier $handler.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $handler.Id -Force -ErrorAction SilentlyContinue
    }

    $watcher.Dispose()
}

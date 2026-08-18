<#
.SYNOPSIS
    Manages the MeowWatch self-hosted Windows CI runner lifecycle on demand.

.DESCRIPTION
    Harden the on-demand runner start path against the 14-day GitHub auto-deletion
    hazard, manage custom labels (meowwatch-ci), sync the action archive cache,
    and verify the runner becomes online and routable.

.PARAMETER Action
    Action to perform: start (default), stop, status, or sync-cache.

.PARAMETER Repo
    GitHub repository in 'owner/repo' format. Defaults to 'PeterShanxin/MeowWatch'.

.PARAMETER RunnerName
    Runner name. Defaults to 'meowwatch-pc'.

.PARAMETER RunnerDir
    Path to the Actions runner installation directory. Defaults to 'C:\actions-runner'.

.PARAMETER CustomLabel
    Custom label required by MeowWatch CI workflows. Defaults to 'meowwatch-ci'.

.PARAMETER TimeoutSec
    Seconds to wait for runner to transition to 'online'. Defaults to 30.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'sync-cache')]
    [string]$Action = 'start',

    [Parameter()]
    [string]$Repo = 'PeterShanxin/MeowWatch',

    [Parameter()]
    [string]$RunnerName = 'meowwatch-pc',

    [Parameter()]
    [string]$RunnerDir = 'C:\actions-runner',

    [Parameter()]
    [string]$CustomLabel = 'meowwatch-ci',

    [Parameter()]
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

function Invoke-Gh {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    # Clear ambient GITHUB_TOKEN to ensure gh uses valid keyring credentials
    $env:GITHUB_TOKEN = $null
    & gh @Args
}

function Get-DartCommand {
    $puroDart = Join-Path $env:USERPROFILE '.puro\envs\stable\flutter\bin\dart.bat'
    if (Test-Path $puroDart) {
        return $puroDart
    }
    $cmd = Get-Command dart -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    $puroFlutter = Join-Path $env:USERPROFILE '.puro\envs\stable\flutter\bin\flutter.bat'
    if (Test-Path $puroFlutter) {
        return $puroFlutter
    }
    throw "Dart/Flutter toolchain not found. Expected Puro at '$puroDart' or 'dart' on PATH."
}

function Get-RunnerProcesses {
    @(Get-CimInstance Win32_Process -Filter "Name = 'Runner.Listener.exe' or Name = 'Runner.Worker.exe'" -ErrorAction SilentlyContinue)
}

function Start-RunnerDetached {
    param([string]$Dir)
    try {
        $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = "cmd.exe /c run.cmd"
            CurrentDirectory = $Dir
        }
        if ($res.ReturnValue -ne 0) {
            throw "Win32_Process.Create returned $($res.ReturnValue)"
        }
    } catch {
        $runCmd = Join-Path $Dir 'run.cmd'
        Start-Process -FilePath $runCmd -WorkingDirectory $Dir -WindowStyle Hidden
    }
}

function Sync-ActionCache {
    Write-Host "Syncing action archive cache..."
    $dart = Get-DartCommand
    $actionCacheScript = Join-Path $PSScriptRoot 'action_cache.dart'
    if (-not (Test-Path $actionCacheScript)) {
        throw "action_cache.dart not found at '$actionCacheScript'."
    }
    & $dart run $actionCacheScript sync --runner-dir $RunnerDir
    if ($LASTEXITCODE -ne 0) {
        throw "Action cache sync failed with exit code $LASTEXITCODE."
    }
}

function Get-RepoRunners {
    $raw = Invoke-Gh api "repos/$Repo/actions/runners"
    if (-not $raw) {
        throw "Failed to query runners for repository '$Repo' via GitHub API."
    }
    return ($raw | ConvertFrom-Json)
}

switch ($Action) {
    'sync-cache' {
        Sync-ActionCache
    }

    'stop' {
        $processes = Get-RunnerProcesses
        if ($processes.Count -gt 0) {
            $pids = ($processes | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
            Write-Host "Stopping runner processes: $pids..."
            $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Write-Host "Runner processes stopped."
        } else {
            Write-Host "No runner processes (Runner.Listener.exe, Runner.Worker.exe) were running."
        }
    }

    'status' {
        if (-not (Test-Path $RunnerDir)) {
            Write-Warning "Runner directory '$RunnerDir' does not exist."
        }
        $runnersData = Get-RepoRunners
        $runner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
        $processes = Get-RunnerProcesses

        Write-Host "Runner Status for '$RunnerName' in '$Repo':"
        if ($runner) {
            Write-Host "  GitHub ID:      $($runner.id)"
            Write-Host "  Status:         $($runner.status)"
            Write-Host "  Busy:           $($runner.busy)"
            Write-Host "  GitHub Version: $($runner.version)"
            $labels = @($runner.labels | ForEach-Object { $_.name })
            Write-Host "  Labels:         $($labels -join ', ')"
        } else {
            Write-Host "  GitHub State:   NOT REGISTERED (total repo runners: $($runnersData.total_count))"
        }

        if (Test-Path $RunnerDir) {
            $binItem = Get-Item (Join-Path $RunnerDir 'bin') -ErrorAction SilentlyContinue
            if ($binItem -and $binItem.Target) {
                Write-Host "  Local Target:   $($binItem.Target)"
            }
            if (Test-Path (Join-Path $RunnerDir '.runner')) {
                Write-Host "  Local Config:   Configured (.runner present)"
            } else {
                Write-Host "  Local Config:   Not configured (.runner missing)"
            }
        }

        if ($processes.Count -gt 0) {
            $procList = ($processes | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
            Write-Host "  Local Procs:    $procList"
        } else {
            Write-Host "  Local Procs:    None"
        }
    }

    'start' {
        if (-not (Test-Path $RunnerDir)) {
            throw "Runner installation directory '$RunnerDir' not found."
        }

        Write-Host "Checking GitHub registration for runner '$RunnerName' in '$Repo'..."
        $runnersData = Get-RepoRunners
        $runner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }

        if (-not $runner) {
            Write-Host "Runner '$RunnerName' is not registered on GitHub (may have been auto-deleted after 14 days idle)."
            $running = Get-RunnerProcesses
            if ($running.Count -gt 0) {
                $pids = ($running | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
                throw "Runner processes are active ($pids), but runner is not registered on GitHub. Stop them before re-registering."
            }

            # Local cleanup if stale config exists
            if (Test-Path (Join-Path $RunnerDir '.runner')) {
                Write-Host "Removing stale local registration (.runner) via config.cmd remove --local..."
                $configCmd = Join-Path $RunnerDir 'config.cmd'
                & $configCmd remove --local
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to remove stale local configuration with config.cmd remove --local (exit code $LASTEXITCODE)."
                }
            }

            # Mint registration token
            Write-Host "Minting fresh runner registration token for '$Repo'..."
            $token = (Invoke-Gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token).Trim()
            if (-not $token) {
                throw "Failed to obtain registration token from GitHub API."
            }

            Write-Host "Re-registering runner '$RunnerName' with custom label '$CustomLabel'..."
            try {
                $configCmd = Join-Path $RunnerDir 'config.cmd'
                & $configCmd --unattended --url "https://github.com/$Repo" --token $token --name $RunnerName --work "_work" --labels $CustomLabel --replace
                if ($LASTEXITCODE -ne 0) {
                    throw "config.cmd registration failed with exit code $LASTEXITCODE."
                }
            } finally {
                # Ensure token is cleared from memory
                $token = $null
            }

            $runnersData = Get-RepoRunners
            $runner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
            if (-not $runner) {
                throw "Runner re-registration completed locally, but GitHub API still reports no runner named '$RunnerName'."
            }
            Write-Host "Runner successfully registered (ID: $($runner.id))."
        } else {
            Write-Host "Runner '$RunnerName' found on GitHub (ID: $($runner.id), Status: $($runner.status))."
            # Verify / add custom label
            $currentLabels = @($runner.labels | ForEach-Object { $_.name })
            if ($CustomLabel -notin $currentLabels) {
                Write-Host "Runner is missing custom label '$CustomLabel'. Adding via GitHub API..."
                Invoke-Gh api -X POST "repos/$Repo/actions/runners/$($runner.id)/labels" -f "labels[]=$CustomLabel" | Out-Null
                Write-Host "Label '$CustomLabel' added."
            }
        }

        # Sync action archive cache before starting listener
        Sync-ActionCache

        # Start runner listener if not already running
        $runningProcesses = Get-RunnerProcesses
        if ($runningProcesses.Count -gt 0) {
            $pids = ($runningProcesses | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
            Write-Host "Runner listener is already running: $pids."
        } else {
            Write-Host "Starting runner listener detached ($RunnerDir\run.cmd)..."
            Start-RunnerDetached -Dir $RunnerDir
        }

        # Wait and verify runner comes online
        Write-Host "Waiting for runner '$RunnerName' to report online (timeout: ${TimeoutSec}s)..."
        $requiredLabels = @('self-hosted', 'Windows', 'X64', $CustomLabel)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $isOnline = $false
        $finalRunner = $null

        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            Start-Sleep -Seconds 2
            $runnersData = Get-RepoRunners
            $finalRunner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
            if ($finalRunner -and $finalRunner.status -eq 'online') {
                $isOnline = $true
                break
            }
        }

        if (-not $isOnline) {
            throw "Runner '$RunnerName' did not come online within $TimeoutSec seconds. Status: $($finalRunner.status). Check '$RunnerDir\_diag\Runner_*.log' for details."
        }

        $finalLabels = @($finalRunner.labels | ForEach-Object { $_.name })
        $missing = @($requiredLabels | Where-Object { $_ -notin $finalLabels })
        if ($missing.Count -gt 0) {
            throw "Runner '$RunnerName' is online but missing required label(s): $($missing -join ', '). Present labels: $($finalLabels -join ', ')"
        }

        Write-Host "Runner '$RunnerName' is online and ready for CI."
        Write-Host "  ID:      $($finalRunner.id)"
        Write-Host "  Version: $($finalRunner.version)"
        Write-Host "  Status:  $($finalRunner.status)"
        Write-Host "  Busy:    $($finalRunner.busy)"
        Write-Host "  Labels:  $($finalLabels -join ', ')"
    }
}

<#
.SYNOPSIS
    Manages the MeowWatch self-hosted Windows CI runner lifecycle on demand.

.DESCRIPTION
    Hardens the on-demand runner start path against the 14-day GitHub auto-deletion
    hazard, enforces the custom 'meowwatch-ci' label, scopes process management
    to this specific runner installation ($RunnerDir), protects active CI jobs against
    unsafe stop, syncs the action archive cache, and verifies runner online state.

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

.PARAMETER Force
    Force stop even if the runner is reported busy by GitHub or executing a job locally.
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
    [int]$TimeoutSec = 30,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Always clear ambient GITHUB_TOKEN so gh uses valid keyring credentials
$env:GITHUB_TOKEN = $null

# Establish repository root from script location (independent of caller cwd)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Gh {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
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
    throw "Dart toolchain not found. Expected Puro Dart at '$puroDart' or 'dart' on PATH."
}

function Test-ProcessBelongsToRunner {
    param(
        [Parameter(Mandatory = $true)]
        $Process,

        [Parameter(Mandatory = $true)]
        [string]$TargetRunnerDir
    )

    if (-not $Process) { return $false }

    $normRunner = [System.IO.Path]::GetFullPath($TargetRunnerDir).TrimEnd('\', '/')
    $exePath = $Process.ExecutablePath

    if ([string]::IsNullOrWhiteSpace($exePath) -and -not [string]::IsNullOrWhiteSpace($Process.CommandLine)) {
        $cmd = $Process.CommandLine.Trim()
        if ($cmd.StartsWith('"')) {
            $endQuote = $cmd.IndexOf('"', 1)
            if ($endQuote -gt 1) {
                $exePath = $cmd.Substring(1, $endQuote - 1)
            }
        } else {
            $space = $cmd.IndexOf(' ')
            if ($space -gt 0) {
                $exePath = $cmd.Substring(0, $space)
            } else {
                $exePath = $cmd
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($exePath)) {
        return $false
    }

    try {
        $normExe = [System.IO.Path]::GetFullPath($exePath)
        $procDir = [System.IO.Path]::GetDirectoryName($normExe)
        if (-not $procDir) { return $false }
        $procParentDir = [System.IO.Path]::GetDirectoryName($procDir)
        if (-not $procParentDir) { return $false }

        $binName = [System.IO.Path]::GetFileName($procDir)
        $isBinDir = ($binName -eq 'bin' -or $binName -like 'bin.*')

        return ($isBinDir -and [string]::Equals($procParentDir, $normRunner, [System.StringComparison]::OrdinalIgnoreCase))
    } catch {
        return $false
    }
}

function Get-RunnerProcesses {
    param([string]$TargetRunnerDir = $RunnerDir)
    $allProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'Runner.Listener.exe' or Name = 'Runner.Worker.exe'" -ErrorAction SilentlyContinue)
    return @($allProcesses | Where-Object { Test-ProcessBelongsToRunner -Process $_ -TargetRunnerDir $TargetRunnerDir })
}

function Resolve-RunnerRecoveryPlan {
    param(
        [Parameter()]
        $RemoteRunner,

        [Parameter()]
        $LocalProcesses,

        [Parameter()]
        [bool]$HasLocalConfig,

        [Parameter()]
        [string]$TargetRepo,

        [Parameter()]
        [string]$TargetRunnerName,

        [Parameter()]
        [string]$TargetLabel
    )

    if ($RemoteRunner) {
        $labels = @($RemoteRunner.labels | ForEach-Object { $_.name })
        $needsLabel = ($TargetLabel -notin $labels)
        return [PSCustomObject]@{
            NeedsRegistration = $false
            NeedsLocalCleanup = $false
            NeedsLabelAddition = $needsLabel
            RefusalReason = $null
            RegistrationArgs = $null
        }
    }

    # Runner is missing from GitHub
    if ($LocalProcesses -and $LocalProcesses.Count -gt 0) {
        $pids = ($LocalProcesses | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
        return [PSCustomObject]@{
            NeedsRegistration = $false
            NeedsLocalCleanup = $false
            NeedsLabelAddition = $false
            RefusalReason = "Runner processes are active ($pids), but runner '$TargetRunnerName' is not registered on GitHub. Stop them before re-registering."
            RegistrationArgs = $null
        }
    }

    return [PSCustomObject]@{
        NeedsRegistration = $true
        NeedsLocalCleanup = $HasLocalConfig
        NeedsLabelAddition = $false
        RefusalReason = $null
        RegistrationArgs = @(
            '--unattended',
            '--url', "https://github.com/$TargetRepo",
            '--name', $TargetRunnerName,
            '--work', '_work',
            '--labels', $TargetLabel,
            '--replace'
        )
    }
}

function Resolve-RunnerStopPlan {
    param(
        [Parameter()]
        $RemoteRunner,

        [Parameter()]
        $LocalProcesses,

        [Parameter()]
        [bool]$QuerySucceeded,

        [Parameter()]
        [string]$QueryError,

        [Parameter()]
        [switch]$ForceStop
    )

    if (-not $LocalProcesses -or $LocalProcesses.Count -eq 0) {
        return [PSCustomObject]@{
            CanStop = $true
            RefusalReason = $null
            Action = 'None'
        }
    }

    if ($ForceStop) {
        return [PSCustomObject]@{
            CanStop = $true
            RefusalReason = $null
            Action = 'Kill'
        }
    }

    # Check local worker process
    $workers = @($LocalProcesses | Where-Object { $_.Name -eq 'Runner.Worker.exe' })
    if ($workers.Count -gt 0) {
        $pids = ($workers | ForEach-Object { $_.ProcessId }) -join ', '
        return [PSCustomObject]@{
            CanStop = $false
            RefusalReason = "Cannot stop runner: a worker job is actively executing locally (Worker PIDs: $pids). Use -Force to override."
            Action = 'Refuse'
        }
    }

    # Check query success
    if (-not $QuerySucceeded) {
        return [PSCustomObject]@{
            CanStop = $false
            RefusalReason = "Cannot safely verify whether runner is busy (GitHub query failed: $QueryError). Refusing to stop while GitHub status is unknown. Use -Force to override."
            Action = 'Refuse'
        }
    }

    # Check GitHub busy status
    if ($RemoteRunner -and $RemoteRunner.busy -eq $true) {
        return [PSCustomObject]@{
            CanStop = $false
            RefusalReason = "Cannot stop runner: GitHub reports runner is currently busy executing a job (ID: $($RemoteRunner.id)). Use -Force to override."
            Action = 'Refuse'
        }
    }

    return [PSCustomObject]@{
        CanStop = $true
        RefusalReason = $null
        Action = 'Kill'
    }
}

function Start-RunnerDetached {
    param([string]$Dir)
    try {
        $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = "cmd.exe /c run.cmd"
            CurrentDirectory = $Dir
        }
        if ($res.ReturnValue -ne 0) {
            throw "Win32_Process.Create returned non-zero code $($res.ReturnValue)"
        }
    } catch {
        throw "Failed to start runner detached via Win32_Process.Create in '$Dir': $($_.Exception.Message). WMI process creation is required to escape the parent Job Object; Start-Process fallback is disabled because it cannot escape the agent Job Object."
    }
}

function Sync-ActionCache {
    param(
        [string]$TargetRunnerDir = $RunnerDir,
        [string]$TargetRepoRoot = $RepoRoot
    )
    $env:GITHUB_TOKEN = $null
    $dart = Get-DartCommand
    $actionCacheScript = Join-Path $PSScriptRoot 'action_cache.dart'
    if (-not (Test-Path $actionCacheScript)) {
        throw "action_cache.dart not found at '$actionCacheScript'."
    }
    Write-Host "Syncing action archive cache for '$TargetRepoRoot'..."
    Push-Location -LiteralPath $TargetRepoRoot
    try {
        & $dart run $actionCacheScript sync --runner-dir $TargetRunnerDir
        if ($LASTEXITCODE -ne 0) {
            throw "Action cache sync failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
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
        Sync-ActionCache -TargetRunnerDir $RunnerDir -TargetRepoRoot $RepoRoot
    }

    'stop' {
        $processes = Get-RunnerProcesses -TargetRunnerDir $RunnerDir
        if ($processes.Count -eq 0) {
            Write-Host "No runner processes found for '$RunnerName' in '$RunnerDir'."
            return
        }

        $querySucceeded = $false
        $queryError = $null
        $remoteRunner = $null

        try {
            $runnersData = Get-RepoRunners
            $remoteRunner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
            $querySucceeded = $true
        } catch {
            $querySucceeded = $false
            $queryError = $_.Exception.Message
        }

        $stopPlan = Resolve-RunnerStopPlan `
            -RemoteRunner $remoteRunner `
            -LocalProcesses $processes `
            -QuerySucceeded $querySucceeded `
            -QueryError $queryError `
            -ForceStop:$Force

        if (-not $stopPlan.CanStop) {
            Write-Error $stopPlan.RefusalReason
            exit 1
        }

        $targetProcesses = $processes

        if (-not $Force) {
            Write-Host "Initial safety check passed. Performing pre-termination quiescence revalidation..."
            Start-Sleep -Milliseconds 500

            $finalProcesses = Get-RunnerProcesses -TargetRunnerDir $RunnerDir
            if ($finalProcesses.Count -eq 0) {
                Write-Host "Runner processes already exited."
                return
            }

            $finalQuerySucceeded = $false
            $finalQueryError = $null
            $finalRemoteRunner = $null

            try {
                $runnersData = Get-RepoRunners
                $finalRemoteRunner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
                $finalQuerySucceeded = $true
            } catch {
                $finalQuerySucceeded = $false
                $finalQueryError = $_.Exception.Message
            }

            $finalStopPlan = Resolve-RunnerStopPlan `
                -RemoteRunner $finalRemoteRunner `
                -LocalProcesses $finalProcesses `
                -QuerySucceeded $finalQuerySucceeded `
                -QueryError $finalQueryError `
                -ForceStop:$false

            if (-not $finalStopPlan.CanStop) {
                Write-Error "Pre-termination revalidation failed: $($finalStopPlan.RefusalReason)"
                exit 1
            }

            $targetProcesses = $finalProcesses
        } else {
            $targetProcesses = Get-RunnerProcesses -TargetRunnerDir $RunnerDir
            if ($targetProcesses.Count -eq 0) {
                Write-Host "No runner processes found for '$RunnerName' in '$RunnerDir'."
                return
            }
        }

        $pids = ($targetProcesses | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
        Write-Host "Stopping runner processes for '$RunnerName' in '$RunnerDir': $pids..."
        $targetProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Write-Host "Runner processes stopped."
    }

    'status' {
        if (-not (Test-Path $RunnerDir)) {
            Write-Warning "Runner directory '$RunnerDir' does not exist."
        }
        $runnersData = Get-RepoRunners
        $runner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
        $processes = Get-RunnerProcesses -TargetRunnerDir $RunnerDir

        Write-Host "Runner Status for '$RunnerName' in '$Repo' (Dir: $RunnerDir):"
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
        $runningProcesses = Get-RunnerProcesses -TargetRunnerDir $RunnerDir
        $hasLocalConfig = Test-Path (Join-Path $RunnerDir '.runner')

        $plan = Resolve-RunnerRecoveryPlan `
            -RemoteRunner $runner `
            -LocalProcesses $runningProcesses `
            -HasLocalConfig $hasLocalConfig `
            -TargetRepo $Repo `
            -TargetRunnerName $RunnerName `
            -TargetLabel $CustomLabel

        if ($plan.RefusalReason) {
            throw $plan.RefusalReason
        }

        if ($plan.NeedsRegistration) {
            Write-Host "Runner '$RunnerName' is not registered on GitHub (may have been auto-deleted after 14 days idle)."
            if ($plan.NeedsLocalCleanup) {
                Write-Host "Removing stale local registration (.runner) via config.cmd remove --local..."
                $configCmd = Join-Path $RunnerDir 'config.cmd'
                & $configCmd remove --local
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to remove stale local configuration with config.cmd remove --local (exit code $LASTEXITCODE)."
                }
            }

            Write-Host "Minting fresh runner registration token for '$Repo'..."
            $token = (Invoke-Gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token).Trim()
            if (-not $token) {
                throw "Failed to obtain registration token from GitHub API."
            }

            Write-Host "Re-registering runner '$RunnerName' with custom label '$CustomLabel'..."
            try {
                $configCmd = Join-Path $RunnerDir 'config.cmd'
                & $configCmd @($plan.RegistrationArgs) --token $token
                if ($LASTEXITCODE -ne 0) {
                    throw "config.cmd registration failed with exit code $LASTEXITCODE."
                }
            } finally {
                $token = $null
            }

            $runnersData = Get-RepoRunners
            $runner = $runnersData.runners | Where-Object { $_.name -eq $RunnerName }
            if (-not $runner) {
                throw "Runner re-registration completed locally, but GitHub API still reports no runner named '$RunnerName'."
            }
            Write-Host "Runner successfully registered (ID: $($runner.id))."
        } elseif ($plan.NeedsLabelAddition) {
            Write-Host "Runner '$RunnerName' found on GitHub (ID: $($runner.id)), but missing custom label '$CustomLabel'. Adding via GitHub API..."
            Invoke-Gh api -X POST "repos/$Repo/actions/runners/$($runner.id)/labels" -f "labels[]=$CustomLabel" | Out-Null
            Write-Host "Label '$CustomLabel' added."
        } else {
            Write-Host "Runner '$RunnerName' found on GitHub (ID: $($runner.id), Status: $($runner.status))."
        }

        # Sync action archive cache before starting listener
        Sync-ActionCache -TargetRunnerDir $RunnerDir -TargetRepoRoot $RepoRoot

        # Check if listener is already running for THIS runner
        $activeProcesses = Get-RunnerProcesses -TargetRunnerDir $RunnerDir
        if ($activeProcesses.Count -gt 0) {
            $pids = ($activeProcesses | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ', '
            Write-Host "Runner listener is already running for '$RunnerDir': $pids."
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

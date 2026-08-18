# runner_lifecycle_test.ps1 - Unit tests for tool/runner.ps1 logic

$ErrorActionPreference = 'Stop'

$ScriptPath = Join-Path $PSScriptRoot '..\..\tool\runner.ps1'
if (-not (Test-Path $ScriptPath)) {
    throw "Runner script not found at $ScriptPath"
}

# Dot-source function definitions by extracting AST functions
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
$functionDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

foreach ($func in $functionDefs) {
    Invoke-Expression $func.Extent.Text
}

$testsPassed = 0
$testsFailed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        $script:testsFailed++
        Write-Error "FAIL: $Message. Expected: '$Expected', Actual: '$Actual'"
    } else {
        $script:testsPassed++
        Write-Host "PASS: $Message"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:testsFailed++
        Write-Error "FAIL: $Message. Expected: True, Actual: False"
    } else {
        $script:testsPassed++
        Write-Host "PASS: $Message"
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:testsFailed++
        Write-Error "FAIL: $Message. Expected: False, Actual: True"
    } else {
        $script:testsPassed++
        Write-Host "PASS: $Message"
    }
}

Write-Host "`n=== Test Group 1: Process Scoping (Test-ProcessBelongsToRunner) ==="
$targetRunner = 'C:\actions-runner'

# Match standard bin
$p1 = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = 'C:\actions-runner\bin\Runner.Listener.exe'
    CommandLine = '"C:\actions-runner\bin\Runner.Listener.exe" run'
}
Assert-True (Test-ProcessBelongsToRunner -Process $p1 -TargetRunnerDir $targetRunner) "Matches standard bin path"

# Match versioned junction bin (e.g. bin.2.336.0)
$p2 = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = 'C:\actions-runner\bin.2.336.0\Runner.Listener.exe'
    CommandLine = '"C:\actions-runner\bin.2.336.0\Runner.Listener.exe" run'
}
Assert-True (Test-ProcessBelongsToRunner -Process $p2 -TargetRunnerDir $targetRunner) "Matches versioned junction bin path (bin.2.336.0)"

# Match worker process
$p3 = [PSCustomObject]@{
    Name = 'Runner.Worker.exe'
    ExecutablePath = 'C:\actions-runner\bin\Runner.Worker.exe'
    CommandLine = '"C:\actions-runner\bin\Runner.Worker.exe" spawnclient 1 2'
}
Assert-True (Test-ProcessBelongsToRunner -Process $p3 -TargetRunnerDir $targetRunner) "Matches Runner.Worker.exe"

# Match via CommandLine fallback when ExecutablePath is null
$p4 = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = $null
    CommandLine = '"C:\actions-runner\bin\Runner.Listener.exe" run'
}
Assert-True (Test-ProcessBelongsToRunner -Process $p4 -TargetRunnerDir $targetRunner) "Matches via CommandLine fallback when ExecutablePath is null"

# Reject nested sub-runner (e.g. Meowcal-Sub in C:\actions-runner\meowcal-sub)
$pSub = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = 'C:\actions-runner\meowcal-sub\bin\Runner.Listener.exe'
    CommandLine = '"C:\actions-runner\meowcal-sub\bin\Runner.Listener.exe" run'
}
Assert-False (Test-ProcessBelongsToRunner -Process $pSub -TargetRunnerDir $targetRunner) "Rejects nested sub-runner installation (meowcal-sub)"

# Reject nested sub-runner with versioned bin
$pSubVer = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = 'C:\actions-runner\meowcal-sub\bin.2.336.0\Runner.Listener.exe'
    CommandLine = '"C:\actions-runner\meowcal-sub\bin.2.336.0\Runner.Listener.exe" run'
}
Assert-False (Test-ProcessBelongsToRunner -Process $pSubVer -TargetRunnerDir $targetRunner) "Rejects nested sub-runner with versioned bin"

# Reject sibling runner directory (C:\actions-runner-other)
$pSibling = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ExecutablePath = 'C:\actions-runner-other\bin\Runner.Listener.exe'
    CommandLine = '"C:\actions-runner-other\bin\Runner.Listener.exe" run'
}
Assert-False (Test-ProcessBelongsToRunner -Process $pSibling -TargetRunnerDir $targetRunner) "Rejects sibling runner directory"

# Reject unrelated process in System32
$pCmd = [PSCustomObject]@{
    Name = 'cmd.exe'
    ExecutablePath = 'C:\Windows\System32\cmd.exe'
    CommandLine = 'cmd.exe /c run.cmd'
}
Assert-False (Test-ProcessBelongsToRunner -Process $pCmd -TargetRunnerDir $targetRunner) "Rejects unrelated process (cmd.exe)"

Write-Host "`n=== Test Group 2: Recovery Plan Logic (Resolve-RunnerRecoveryPlan) ==="

# Case 1: Remote runner healthy with custom label
$healthyRemote = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'offline'
    labels = @(
        [PSCustomObject]@{ name = 'self-hosted' },
        [PSCustomObject]@{ name = 'Windows' },
        [PSCustomObject]@{ name = 'X64' },
        [PSCustomObject]@{ name = 'meowwatch-ci' }
    )
}
$plan1 = Resolve-RunnerRecoveryPlan `
    -RemoteRunner $healthyRemote `
    -LocalProcesses @() `
    -HasLocalConfig $true `
    -TargetRepo 'PeterShanxin/MeowWatch' `
    -TargetRunnerName 'meowwatch-pc' `
    -TargetLabel 'meowwatch-ci'

Assert-False $plan1.NeedsRegistration "Healthy runner does not need registration"
Assert-False $plan1.NeedsLocalCleanup "Healthy runner does not need local cleanup"
Assert-False $plan1.NeedsLabelAddition "Healthy runner does not need label addition"
Assert-Equal $plan1.RefusalReason $null "Healthy runner has no refusal reason"

# Case 2: Remote runner healthy but missing custom label
$remoteMissingLabel = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'offline'
    labels = @(
        [PSCustomObject]@{ name = 'self-hosted' },
        [PSCustomObject]@{ name = 'Windows' },
        [PSCustomObject]@{ name = 'X64' }
    )
}
$plan2 = Resolve-RunnerRecoveryPlan `
    -RemoteRunner $remoteMissingLabel `
    -LocalProcesses @() `
    -HasLocalConfig $true `
    -TargetRepo 'PeterShanxin/MeowWatch' `
    -TargetRunnerName 'meowwatch-pc' `
    -TargetLabel 'meowwatch-ci'

Assert-False $plan2.NeedsRegistration "Runner missing label uses API label addition, not re-registration"
Assert-True $plan2.NeedsLabelAddition "Runner missing label flags NeedsLabelAddition = true"

# Case 3: Runner missing on GitHub (14-day deletion), active processes exist -> REFUSE
$activeProc = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ProcessId = 1234
    ExecutablePath = 'C:\actions-runner\bin\Runner.Listener.exe'
}
$plan3 = Resolve-RunnerRecoveryPlan `
    -RemoteRunner $null `
    -LocalProcesses @($activeProc) `
    -HasLocalConfig $true `
    -TargetRepo 'PeterShanxin/MeowWatch' `
    -TargetRunnerName 'meowwatch-pc' `
    -TargetLabel 'meowwatch-ci'

Assert-False $plan3.NeedsRegistration "Registration blocked when active processes exist"
Assert-True ($plan3.RefusalReason -like "*Runner processes are active*") "Refusal reason explains active processes block re-registration"

# Case 4: Runner missing on GitHub (14-day deletion), stale .runner exists -> CLEANUP + REGISTER
$plan4 = Resolve-RunnerRecoveryPlan `
    -RemoteRunner $null `
    -LocalProcesses @() `
    -HasLocalConfig $true `
    -TargetRepo 'PeterShanxin/MeowWatch' `
    -TargetRunnerName 'meowwatch-pc' `
    -TargetLabel 'meowwatch-ci'

Assert-True $plan4.NeedsRegistration "14-day deleted runner triggers registration"
Assert-True $plan4.NeedsLocalCleanup "Stale local config triggers local cleanup"
Assert-True ($plan4.RegistrationArgs -contains 'meowwatch-ci') "Registration args include 'meowwatch-ci'"
Assert-True ($plan4.RegistrationArgs -contains 'meowwatch-pc') "Registration args include 'meowwatch-pc'"
Assert-True ($plan4.RegistrationArgs -contains '--replace') "Registration args include '--replace'"
Assert-True ($plan4.RegistrationArgs -contains '_work') "Registration args include '_work'"

# Case 5: Runner missing on GitHub, clean directory -> REGISTER without cleanup
$plan5 = Resolve-RunnerRecoveryPlan `
    -RemoteRunner $null `
    -LocalProcesses @() `
    -HasLocalConfig $false `
    -TargetRepo 'PeterShanxin/MeowWatch' `
    -TargetRunnerName 'meowwatch-pc' `
    -TargetLabel 'meowwatch-ci'

Assert-True $plan5.NeedsRegistration "Clean missing runner triggers registration"
Assert-False $plan5.NeedsLocalCleanup "Clean missing runner does not need local cleanup"

Write-Host "`n=== Test Group 3: Stop Safety (Resolve-RunnerStopPlan) ==="

# Case 1: No local processes
$stopPlan1 = Resolve-RunnerStopPlan `
    -RemoteRunner $healthyRemote `
    -LocalProcesses @() `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $stopPlan1.CanStop "Can stop when no processes running"
Assert-Equal $stopPlan1.Action 'None' "Action is None when no processes running"

# Case 2: Local worker running, no force -> REFUSE
$workerProc = [PSCustomObject]@{
    Name = 'Runner.Worker.exe'
    ProcessId = 5678
    ExecutablePath = 'C:\actions-runner\bin\Runner.Worker.exe'
}
$stopPlan2 = Resolve-RunnerStopPlan `
    -RemoteRunner $healthyRemote `
    -LocalProcesses @($activeProc, $workerProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-False $stopPlan2.CanStop "Refuses stop when local Runner.Worker.exe is active"
Assert-True ($stopPlan2.RefusalReason -like "*worker job is actively executing locally*") "Refusal reason mentions active worker"

# Case 3: Local worker running + Force -> ALLOW
$stopPlan3 = Resolve-RunnerStopPlan `
    -RemoteRunner $healthyRemote `
    -LocalProcesses @($activeProc, $workerProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$true

Assert-True $stopPlan3.CanStop "Allows stop with -Force even if worker is active"
Assert-Equal $stopPlan3.Action 'Kill' "Action is Kill with -Force"

# Case 4: Remote runner busy on GitHub (busy: true), no force -> REFUSE
$busyRemote = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'online'
    busy = $true
    labels = @([PSCustomObject]@{ name = 'meowwatch-ci' })
}
$stopPlan4 = Resolve-RunnerStopPlan `
    -RemoteRunner $busyRemote `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-False $stopPlan4.CanStop "Refuses stop when GitHub reports runner busy: true"
Assert-True ($stopPlan4.RefusalReason -like "*runner is currently busy executing a job*") "Refusal reason mentions GitHub busy state"

# Case 5: Remote runner busy on GitHub + Force -> ALLOW
$stopPlan5 = Resolve-RunnerStopPlan `
    -RemoteRunner $busyRemote `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$true

Assert-True $stopPlan5.CanStop "Allows stop with -Force when runner is busy on GitHub"

# Case 6: GitHub API query failed (network/auth issue), no force -> FAIL CLOSED (REFUSE)
$stopPlan6 = Resolve-RunnerStopPlan `
    -RemoteRunner $null `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $false `
    -QueryError "HTTP 503 Service Unavailable" `
    -ForceStop:$false

Assert-False $stopPlan6.CanStop "Fails closed (refuses stop) when GitHub cannot be queried"
Assert-True ($stopPlan6.RefusalReason -like "*Cannot safely verify whether runner is busy*") "Refusal reason explains query failure"

# Case 7: GitHub API query failed + Force -> ALLOW
$stopPlan7 = Resolve-RunnerStopPlan `
    -RemoteRunner $null `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $false `
    -QueryError "HTTP 503 Service Unavailable" `
    -ForceStop:$true

Assert-True $stopPlan7.CanStop "Allows stop with -Force when GitHub query failed"

# Case 8: Idle runner (busy: false, no worker) -> ALLOW
$idleRemote = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'online'
    busy = $false
    labels = @([PSCustomObject]@{ name = 'meowwatch-ci' })
}
$stopPlan8 = Resolve-RunnerStopPlan `
    -RemoteRunner $idleRemote `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $stopPlan8.CanStop "Allows stop when runner is idle (busy: false, no worker)"
Assert-Equal $stopPlan8.Action 'Kill' "Action is Kill for idle runner"

# Case 9: TOCTOU Revalidation - State changes from idle on first check to busy on final check
$initialRemote9 = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'online'
    busy = $false
    labels = @([PSCustomObject]@{ name = 'meowwatch-ci' })
}
$firstCheckPlan9 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $firstCheckPlan9.CanStop "TOCTOU: Initial check allows stop when idle"

$finalRemote9 = [PSCustomObject]@{
    id = 22
    name = 'meowwatch-pc'
    status = 'online'
    busy = $true
    labels = @([PSCustomObject]@{ name = 'meowwatch-ci' })
}
$finalCheckPlan9 = Resolve-RunnerStopPlan `
    -RemoteRunner $finalRemote9 `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-False $finalCheckPlan9.CanStop "TOCTOU: Final revalidation refuses stop when state transitioned to busy: true"
Assert-True ($finalCheckPlan9.RefusalReason -like "*currently busy executing a job*") "TOCTOU: Final revalidation states runner is busy"

# Case 10: TOCTOU Revalidation - State changes from idle on first check to worker process active on final check
$firstCheckPlan10 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $firstCheckPlan10.CanStop "TOCTOU: Initial check allows stop when no worker"

$finalProcesses10 = @($activeProc, $workerProc)
$finalCheckPlan10 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses $finalProcesses10 `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-False $finalCheckPlan10.CanStop "TOCTOU: Final revalidation refuses stop when Runner.Worker.exe appeared during quiescence"
Assert-True ($finalCheckPlan10.RefusalReason -like "*worker job is actively executing locally*") "TOCTOU: Final revalidation identifies active worker"

# Case 11: TOCTOU Revalidation - Initial check passes, but GitHub query fails during final revalidation
$firstCheckPlan11 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $firstCheckPlan11.CanStop "TOCTOU: Initial check passes before transient network failure"

$finalCheckPlan11 = Resolve-RunnerStopPlan `
    -RemoteRunner $null `
    -LocalProcesses @($activeProc) `
    -QuerySucceeded $false `
    -QueryError "Connection reset by peer" `
    -ForceStop:$false

Assert-False $finalCheckPlan11.CanStop "TOCTOU: Final revalidation fails closed when GitHub query fails"

# Case 12: TOCTOU Revalidation - Initial check passes with PID A, process list refreshed to PID B on revalidation
$procA = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ProcessId = 1001
    ExecutablePath = 'C:\actions-runner\bin\Runner.Listener.exe'
}
$procB = [PSCustomObject]@{
    Name = 'Runner.Listener.exe'
    ProcessId = 1002
    ExecutablePath = 'C:\actions-runner\bin\Runner.Listener.exe'
}
$firstCheckPlan12 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @($procA) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $firstCheckPlan12.CanStop "TOCTOU: Initial check passes with PID 1001"

$finalCheckPlan12 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @($procB) `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $finalCheckPlan12.CanStop "TOCTOU: Final revalidation accepts refreshed PID 1002"
Assert-Equal $finalCheckPlan12.Action 'Kill' "Action is Kill for refreshed PID"

# Case 13: TOCTOU Revalidation - Runner exited on its own during quiescence
$finalCheckPlan13 = Resolve-RunnerStopPlan `
    -RemoteRunner $initialRemote9 `
    -LocalProcesses @() `
    -QuerySucceeded $true `
    -QueryError $null `
    -ForceStop:$false

Assert-True $finalCheckPlan13.CanStop "TOCTOU: Revalidation returns CanStop=true when processes already exited"
Assert-Equal $finalCheckPlan13.Action 'None' "Action is None when processes already exited"

Write-Host "`n=== Test Group 4: Toolchain & Repo Independence ==="

# Verify Dart command resolution
$dartCmd = Get-DartCommand
Assert-True (Test-Path $dartCmd) "Resolved Dart executable exists: '$dartCmd'"
Assert-True ($dartCmd -notlike "*flutter.bat*") "Resolved Dart executable is not flutter.bat"

Write-Host "`n==============================================="
Write-Host "Test Results: $testsPassed passed, $testsFailed failed"
Write-Host "==============================================="

if ($testsFailed -gt 0) {
    exit 1
}

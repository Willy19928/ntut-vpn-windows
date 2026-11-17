#Requires -Version 5.1
<#
Regression test for the restart race fixed in 1.2.6: when OpenConnect restarts,
the previous session's state files may be held open or left behind. The hook must
not abort, and leftover markers from another session must never be trusted.
Runs the real hook.js, route-worker.js and supervisor.cs with a dummy route script.
It does not connect, elevate, or change any network settings.
#>
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'src'
$work = Join-Path ([IO.Path]::GetTempPath()) ('NTUT-VPN-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$cscript = Join-Path $env:SystemRoot 'System32\cscript.exe'
$failed = 0
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $script:failed++ }
}
function Start-Script([string]$file, [string]$reason, [string]$token, [string]$state, [string]$route) {
    $info = New-Object Diagnostics.ProcessStartInfo($cscript, "//Nologo //E:JScript `"$file`"")
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.EnvironmentVariables['reason'] = $reason
    $info.EnvironmentVariables['NTUT_EVENT_TOKEN'] = $token
    $info.EnvironmentVariables['NTUT_STATE_FILE'] = $state
    $info.EnvironmentVariables['NTUT_ROUTE_WORKER'] = Join-Path $src 'route-worker.js'
    $info.EnvironmentVariables['NTUT_ROUTE_SCRIPT'] = $route
    [Diagnostics.Process]::Start($info)
}
function New-Token { [guid]::NewGuid().ToString('N') }
$suffixes = @('.started', '.cancel', '.ready', '.cleanup', '.recovering', '.error', '.command')
try {
    $state = Join-Path $work 'state.txt'
    $route = Join-Path $work 'route-ok.js'
    [IO.File]::WriteAllText($route, 'WScript.Quit(0);')
    $old = New-Token; $new = New-Token

    # 1. The 1.2.5 failure: the state file is held open (as the old supervisor's
    #    poll did) for longer than the hook's retries while pre-init runs.
    [IO.File]::WriteAllText($state, "${old}:disconnected:0:0")
    foreach ($s in $suffixes) { [IO.File]::WriteAllText($state + $s, $old) }
    $held = New-Object IO.FileStream($state, 'Open', 'Read', 'Read')
    try {
        $p = Start-Script (Join-Path $src 'hook.js') 'pre-init' $new $state $route
        $p.WaitForExit(); $code = $p.ExitCode
    } finally { $held.Dispose() }
    Check 'pre-init finishes even when the state file is locked' ($code -eq 0)
    Check 'pre-init still removes the other leftover files' (@($suffixes | Where-Object { Test-Path ($state + $_) }).Count -eq 0)

    # 2. A leftover cancel marker from another session must not skip setup.
    [IO.File]::WriteAllText($state + '.cancel', $old)
    $p = Start-Script (Join-Path $src 'route-worker.js') 'connect' $new $state $route
    $p.WaitForExit()
    Check 'stale cancel marker is ignored; setup runs' ([IO.File]::ReadAllText($state).StartsWith("${new}:connected:"))
    Check 'ready marker carries this session token' ([IO.File]::ReadAllText($state + '.ready') -eq $new)

    # 3. This session's own cancel marker still cancels setup.
    Remove-Item ($state + '.ready')
    [IO.File]::WriteAllText($state + '.cancel', $new)
    $p = Start-Script (Join-Path $src 'route-worker.js') 'connect' $new $state $route
    $p.WaitForExit()
    Check 'own cancel marker still cancels setup' ([IO.File]::ReadAllText($state).StartsWith("${new}:cancelled:"))

    # 4. Disconnect writes a token-tagged cleanup marker.
    $p = Start-Script (Join-Path $src 'route-worker.js') 'disconnect' $new $state $route
    $p.WaitForExit()
    Check 'cleanup marker carries this session token' ([IO.File]::ReadAllText($state + '.cleanup') -eq "${new}:0")

    # 5. Supervisor reads never block deletion, and it clears leftovers itself.
    if (!('NtutVpn.Supervisor' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $src 'supervisor.cs'))) }
    Check 'supervisor reads the state file' ([NtutVpn.Supervisor]::ReadShared($state).StartsWith("${new}:"))
    Check 'supervisor read of a missing file is empty' ([NtutVpn.Supervisor]::ReadShared($state + '.missing') -eq '')
    $shared = New-Object IO.FileStream($state, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $p = Start-Script (Join-Path $src 'hook.js') 'pre-init' (New-Token) $state $route
        $p.WaitForExit(); $code = $p.ExitCode
    } finally { $shared.Dispose() }
    Check 'hook can delete the state file while the supervisor reads it' (($code -eq 0) -and !(Test-Path $state))
    foreach ($s in @('') + $suffixes) { [IO.File]::WriteAllText($state + $s, $old) }
    [NtutVpn.Supervisor]::ClearSessionFiles($state)
    Check 'supervisor clears leftover session files' (@(@('') + $suffixes | Where-Object { Test-Path ($state + $_) }).Count -eq 0)
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed) { Write-Host "$failed check(s) failed."; exit 1 }
Write-Host 'All state race checks passed.'

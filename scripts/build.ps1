#requires -Version 5.1
<#
Builds dist\NTUT-VPN.ps1 and dist\NTUT-VPN.exe from src\ and vendor\.
Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
PS2EXE is downloaded from a pinned commit and checked against a pinned SHA-256.
#>
[CmdletBinding()]
param(
    [switch]$SkipExe,
    [switch]$SelfTest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.2.6.0'
$Ps2ExeCommit = '05c62615b33864c177f5de8e56e06e4c7f34adbb'
$Ps2ExeSha256 = '94613E703FA2EC67A01255E5917A056A9406FD31C557685B7AE76417F706A09A'

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'src'
$vendor = Join-Path $root 'vendor\openconnect-9.21'
$obj = Join-Path $root 'obj'
$dist = Join-Path $root 'dist'
$null = New-Item -ItemType Directory -Force -Path $obj, $dist
$utf8Bom = New-Object Text.UTF8Encoding($true)

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

# Fixed entry order and timestamps keep the ZIP bytes identical between builds.
function New-PayloadZip([string[]]$Paths) {
    Add-Type -AssemblyName System.IO.Compression
    $stamp = New-Object DateTimeOffset(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $memory = New-Object IO.MemoryStream
    $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($path in $Paths) {
            $entry = $zip.CreateEntry([IO.Path]::GetFileName($path), [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $stamp
            $data = [IO.File]::ReadAllBytes($path)
            $stream = $entry.Open()
            try { $stream.Write($data, 0, $data.Length) } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    return ,$memory.ToArray()
}

function Replace-Once([string]$Text, [string]$Old, [string]$New, [int]$Count = 1) {
    $found = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($found -ne $Count) { throw "Expected $Count occurrence(s) of '$Old', found $found." }
    return $Text.Replace($Old, $New)
}

Write-Host '== Verify vendored OpenConnect files'
$manifest = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $vendor 'SHA256SUMS'))) {
    if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)$') { $manifest[$Matches[2]] = $Matches[1].ToUpperInvariant() }
}
foreach ($name in $manifest.Keys) {
    $actual = Get-Sha256Hex ([IO.File]::ReadAllBytes((Join-Path $vendor $name)))
    if ($actual -ne $manifest[$name]) { throw "SHA-256 mismatch: vendor\openconnect-9.21\$name" }
}

Write-Host '== Pack runtime and source payloads'
$runtimeFiles = @(
    (Join-Path $src 'hook.js'),
    'iconv.dll', 'libgcc_s_seh-1.dll', 'libgmp-10.dll', 'libgnutls-30.dll', 'libhogweed-6.dll',
    'libintl-8.dll', 'liblz4.dll', 'libnettle-8.dll', 'libopenconnect-5.dll', 'libstoken-1.dll',
    'libtasn1-6.dll', 'libwinpthread-1.dll', 'libxml2-2.dll', 'openconnect.exe',
    (Join-Path $src 'route-worker.js'),
    (Join-Path $src 'vpnc-script-win.js'),
    'wintun.dll', 'zlib1.dll'
) | ForEach-Object { if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $vendor $_ } }
if (@($runtimeFiles | Where-Object { $_.StartsWith($vendor) }).Count -ne $manifest.Count) { throw 'Vendored file list and SHA256SUMS differ.' }
$runtimeZip = New-PayloadZip $runtimeFiles
$sourceZip = New-PayloadZip @('route-helpers.js', 'hook.js', 'route-worker.js', 'supervisor.cs' | ForEach-Object { Join-Path $src $_ })

Write-Host '== Generate NTUT-VPN.ps1'
$supervisor = [IO.File]::ReadAllText((Join-Path $src 'supervisor.cs')).Replace("`r`n", "`n").Replace("`n", "`r`n")
$script = [IO.File]::ReadAllText((Join-Path $src 'NTUT-VPN.ps1'))
$script = Replace-Once $script '__SUPERVISOR_CS__' $supervisor 2
$script = Replace-Once $script '__RUNTIME_SHA256__' (Get-Sha256Hex $runtimeZip)
$script = Replace-Once $script '__SOURCE_ZIP_BASE64__' ([Convert]::ToBase64String($sourceZip))
$script = Replace-Once $script '__RUNTIME_ZIP_BASE64__' ([Convert]::ToBase64String($runtimeZip))
$ps1Out = Join-Path $dist 'NTUT-VPN.ps1'
[IO.File]::WriteAllText($ps1Out, $script, $utf8Bom)


if (!$SkipExe) {
    Write-Host '== Prepare PS2EXE'
    $ps2exe = Join-Path $obj "ps2exe-$($Ps2ExeCommit.Substring(0, 12)).ps1"
    if (!(Test-Path -LiteralPath $ps2exe)) {
        $url = "https://raw.githubusercontent.com/MScholtes/PS2EXE/$Ps2ExeCommit/Module/ps2exe.ps1"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $ps2exe
    }
    if ((Get-Sha256Hex ([IO.File]::ReadAllBytes($ps2exe))) -ne $Ps2ExeSha256) {
        Remove-Item -LiteralPath $ps2exe -Force
        throw 'PS2EXE SHA-256 mismatch.'
    }

    Write-Host '== Compile NTUT-VPN.exe'
    # The EXE elevates by restarting itself instead of powershell.exe -File <script>.
    $embedded = Replace-Once $script `
        ("    `$hostExe = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'`r`n" +
         "    `$arguments = '-NoProfile -ExecutionPolicy Bypass -File `"' + `$PSCommandPath + '`" -VpnUser `"' + `$VpnUser + '`"'") `
        ("    `$hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName`r`n" +
         "    `$arguments = '-VpnUser `"' + `$VpnUser + '`"'")
    $embeddedPath = Join-Path $obj 'NTUT-VPN-embedded.ps1'
    [IO.File]::WriteAllText($embeddedPath, $embedded, $utf8Bom)
    $exeOut = Join-Path $dist 'NTUT-VPN.exe'
    if (Test-Path -LiteralPath $exeOut) { Remove-Item -LiteralPath $exeOut -Force }
    # PS2EXE reads unset variables, which strict mode rejects.
    Set-StrictMode -Off
    . $ps2exe
    $icon = Join-Path $root 'assets\NTUT-VPN.ico'
    if (!(Test-Path -LiteralPath $icon)) { throw 'assets\NTUT-VPN.ico is missing.' }
    Invoke-ps2exe -inputFile $embeddedPath -outputFile $exeOut -x64 -supportOS `
        -iconFile $icon -title 'NTUT VPN' -product 'NTUT VPN' -version $Version
    if (!(Test-Path -LiteralPath $exeOut)) { throw 'PS2EXE did not produce NTUT-VPN.exe.' }

    # A file scanner can hold a freshly written EXE for a while; wait until it can be read in full.
    $expected = (Get-Item -LiteralPath $exeOut).Length
    $exeBytes = $null
    for ($i = 0; $i -lt 180 -and $null -eq $exeBytes; $i++) {
        try {
            $read = [IO.File]::ReadAllBytes($exeOut)
            if ($read.Length -eq $expected) { $exeBytes = $read }
        } catch { }
        if ($null -eq $exeBytes) { Start-Sleep -Seconds 1 }
    }
    if ($null -eq $exeBytes) { throw 'NTUT-VPN.exe could not be read back after compiling.' }

    if ($SelfTest) {
        Write-Host '== Self test'
        # Windows may refuse to run programs from a network share, so test a local copy.
        $testDir = Join-Path ([IO.Path]::GetTempPath()) ('NTUT-VPN-build-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $testDir
        $testExe = Join-Path $testDir 'NTUT-VPN.exe'
        try {
            [IO.File]::WriteAllBytes($testExe, $exeBytes)
            & $testExe -SelfTest
            if ($LASTEXITCODE -ne 0) { throw "Self test failed with exit code $LASTEXITCODE." }
        } finally {
            Remove-Item -LiteralPath $testExe -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $testDir -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host '== Write SHA256SUMS'
$sums = @((Get-Sha256Hex ([IO.File]::ReadAllBytes($ps1Out))).ToLowerInvariant() + '  NTUT-VPN.ps1')
if (!$SkipExe) { $sums += (Get-Sha256Hex $exeBytes).ToLowerInvariant() + '  NTUT-VPN.exe' }
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS'), (($sums -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
$sums | ForEach-Object { Write-Host $_ }

#requires -Version 5.1
<#
NTUT VPN - single-file Windows x64 tool.
Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NTUT-VPN.ps1
The execution-policy option affects only that PowerShell process.
Normal connection requests UAC elevation; -SelfTest does not connect or elevate.
OpenConnect is the unmodified v9.21 official tagged CI artifact, not a local build.
Official package URL:
https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=persist-windows-builds-for-tagged-releases
Original installer SHA-256: 6EE9E8EB9BC59EF70BB0717DF7F99703F8A2CCD11D8E45D58A61F9A2E6EF7D00
The embedded ZIP is packaging, not encryption. No password is embedded or saved.
Optional: -ExportSource <new ZIP path> exports the local supervisor/callback source.
Normal exit removes this invocation's private runtime files. Forced window closure
can leave runtime files. TLS verification stays enabled; there is no kill switch.
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$ExportSource = '',
    [string]$VpnUser = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hadFailure = $false
$failureMessage = ''
function Stop-WithVisibleError([string]$Message) {
    Write-Host ('[錯誤] ' + $Message) -ForegroundColor Red
    if (!$SelfTest -and ![Console]::IsInputRedirected) {
        try { $null = Read-Host '請先查看或複製上方錯誤，按 Enter 才關閉視窗' } catch { }
    }
}
trap {
    if ($_.Exception -is [Management.Automation.PipelineStoppedException]) { exit 130 }
    Stop-WithVisibleError $_.Exception.Message
    exit 1
}
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$payloadHash = '__RUNTIME_SHA256__'
$runtimeDir = $null
$password = $null
$sessionLock = $null
$runtimeNames = New-Object 'System.Collections.Generic.List[string]'
if ($ExportSource) {
    $sourceBytes = [Convert]::FromBase64String('__SOURCE_ZIP_BASE64__')
    $stream = New-Object IO.FileStream([IO.Path]::GetFullPath($ExportSource), [IO.FileMode]::CreateNew)
    try { $stream.Write($sourceBytes, 0, $sourceBytes.Length) } finally { $stream.Dispose() }
    Write-Host "原始碼已匯出：$ExportSource"
    return
}
if ($VpnUser -and $VpnUser -notmatch '^[A-Za-z0-9_.@-]+$') { throw 'Invalid VPN username.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try { $isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
finally { $identity.Dispose() }
if (!$SelfTest -and !$isAdmin) {
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -VpnUser "' + $VpnUser + '"'
    try { $null = Start-Process -FilePath $hostExe -ArgumentList $arguments -Verb RunAs }
    catch { Write-Error '未取得系統管理員授權，未建立 VPN。' }
    return
}
try {
    $created = $false
    $mutexName = 'Local\NTUT-OpenConnect-Supervisor'
    if ($SelfTest) { $mutexName += '-SelfTest-' + [guid]::NewGuid().ToString('N') }
    $sessionLock = New-Object Threading.Mutex($true, $mutexName, [ref]$created)
    if (!$created) { throw '此登入工作階段已有北科大 VPN 工具執行中。' }
    $bytes = [Convert]::FromBase64String('__RUNTIME_ZIP_BASE64__')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($actualHash -ne $payloadHash) { throw '內嵌套件完整性檢查失敗。' }

    $runtimeDir = Join-Path ([IO.Path]::GetTempPath()) ('NTUT-VPN-' + [Guid]::NewGuid().ToString('N'))
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    if ($VpnUser -and $VpnUser -notmatch '^[A-Za-z0-9_.@-]+$') { throw 'Invalid VPN username.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        foreach ($sid in @($identity.User, [Security.Principal.SecurityIdentifier]'S-1-5-18', [Security.Principal.SecurityIdentifier]'S-1-5-32-544')) {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
    } finally { $identity.Dispose() }
    $null = [IO.Directory]::CreateDirectory($runtimeDir, $acl)
    Add-Type -AssemblyName System.IO.Compression
    $memory = New-Object IO.MemoryStream(,$bytes)
    $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($entry in $zip.Entries) {
            if (!$entry.Name -or $entry.FullName -ne $entry.Name -or $entry.Name -eq '..') { throw '封裝路徑無效。' }
            $target = Join-Path $runtimeDir $entry.Name
            $runtimeNames.Add($entry.Name)
            $inputStream = $entry.Open()
            try {
                $outputStream = New-Object IO.FileStream($target, [IO.FileMode]::CreateNew)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
            } finally { $inputStream.Dispose() }
        }
    } finally { $zip.Dispose(); $memory.Dispose() }
    $bytes = $null
    $exe = Join-Path $runtimeDir 'openconnect.exe'
    if ($SelfTest) {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $exe
        $startInfo.Arguments = '--version'
        $startInfo.WorkingDirectory = $runtimeDir
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['LC_ALL'] = 'C'
        $child = New-Object Diagnostics.Process
        $child.StartInfo = $startInfo
        try {
            $null = $child.Start()
            $version = $child.StandardOutput.ReadToEnd()
            $diagnostic = $child.StandardError.ReadToEnd()
            $child.WaitForExit()
            Write-Host $version
            if ($diagnostic) { Write-Host $diagnostic }
            if ($child.ExitCode -ne 0 -or $version -notmatch 'v9\.21' -or $version -notmatch '\bgp\b') { throw 'CLI 自我檢查失敗。' }
        } finally { $child.Dispose() }
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $runtimeDir 'wintun.dll')
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'WireGuard LLC') { throw 'Wintun 簽章驗證失敗。' }
        # Compile the exact connection supervisor too, without connecting or creating a network adapter.
        if (!('NtutVpn.Supervisor' -as [type])) { Add-Type -TypeDefinition @'
__SUPERVISOR_CS__
'@ }
        Write-Host 'PASS：內嵌套件雜湊、解壓縮、DLL 載入、v9.21／gp、Wintun 簽章、重連程式編譯。未連線或變更網路。'
        return
    }
    if (!('NtutVpn.Supervisor' -as [type])) { Add-Type -TypeDefinition @'
__SUPERVISOR_CS__
'@ }
    $runtimeNames.Add('state.txt')
    foreach ($suffix in @('.started','.cancel','.ready','.cleanup','.recovering','.error','.command')) { $runtimeNames.Add('state.txt' + $suffix) }
    Write-Host '=== 北科大 VPN / vpn.ntut.edu.tw ==='
    if (!$VpnUser) { $VpnUser = (Read-Host '請輸入 VPN 帳號').Trim() }
    if ($VpnUser -notmatch '^[A-Za-z0-9_.@-]+$') { throw '帳號未填寫或含有不支援的字元。' }
    Write-Host "帳號：$VpnUser　　按 Ctrl+C 正常斷線；請勿直接關閉視窗。"
    Write-Host '密碼不存檔；伺服器憑證驗證開啟；不修改防火牆規則。'
    $password = Read-Host '請輸入 VPN 密碼' -AsSecureString
    if ($password.Length -eq 0) { throw '未輸入密碼。' }
    $result = [NtutVpn.Supervisor]::Run($exe, (Join-Path $runtimeDir 'hook.js'), (Join-Path $runtimeDir 'vpnc-script-win.js'), (Join-Path $runtimeDir 'state.txt'), $VpnUser, $password)
    Write-Host "VPN 工具已停止（代碼 $result）。"
    if ($result -ne 0 -and $result -ne 130) {
        $hadFailure = $true
        $failureMessage = "連線未成功（代碼 $result），請查看上方的連線或網路設定錯誤。"
    }
} catch {
    $hadFailure = $true
    $failureMessage = $_.Exception.Message
} finally {
    if ($null -ne $password) { $password.Dispose() }
    if ($null -ne $sessionLock) { $sessionLock.Dispose() }
    if ($null -ne $runtimeDir -and (Test-Path -LiteralPath $runtimeDir)) {
        $full = [IO.Path]::GetFullPath($runtimeDir)
        $prefix = Join-Path ([IO.Path]::GetTempPath()) 'NTUT-VPN-'
        if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            foreach ($name in $runtimeNames) {
                $file = Join-Path $full $name
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    try { Remove-Item -LiteralPath $file -Force } catch { Write-Warning "未能清除本次暫存檔：$file" }
                }
            }
            $lockDir = Join-Path $full 'state.txt.lock'
            if ([IO.Directory]::Exists($lockDir) -and [IO.Directory]::GetFileSystemEntries($lockDir).Length -eq 0) { [IO.Directory]::Delete($lockDir, $false) }
            try { [IO.Directory]::Delete($full, $false) } catch { Write-Warning "本次暫存資料夾尚未清除：$full" }
        }
    }
}

if ($hadFailure) {
    Stop-WithVisibleError $failureMessage
    exit 1
}
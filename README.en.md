# NTUT VPN for Windows

[中文](README.md) | **English**

A single-file Windows tool for connecting to the National Taipei University of Technology VPN (`vpn.ntut.edu.tw`, GlobalProtect). OpenConnect and all of its dependencies are packed into one `NTUT-VPN.exe`, so no separate client is needed. For macOS, see [ntut-vpn-mac](https://github.com/Willy19928/ntut-vpn-mac).

> This is a personal tool. It is **not** official university software and is not affiliated with NTUT.

## Features

- **Automatic reconnect**: the university's official client is forcibly disconnected after about 4 hours. This tool logs in again on its own when the connection drops, without asking for your credentials again.
- **One EXE**: bundles the official OpenConnect v9.21 Windows build, GnuTLS and the Wintun driver library.
- **Nothing saved**: you type the username and password at every start. The password never goes on a command line, into a config file or into a log.
- **Errors stay visible**: on failure the window waits for Enter, so the error can be read and copied.
- No kill switch and no firewall changes; server TLS certificate verification stays on.

## Requirements

- Windows 10/11 x64 (Windows only)
- Windows PowerShell 5.1 (built into Windows)
- Administrator rights (needed to create the VPN adapter; a UAC prompt appears at start)

## Usage

1. Download `NTUT-VPN.exe` from [Releases](https://github.com/Willy19928/ntut-vpn-windows/releases/latest) and optionally check it against `SHA256SUMS` on the same page.
2. Run `NTUT-VPN.exe` and accept UAC.
3. Enter your VPN username and password (the password is not echoed).
4. Once the connected message appears, campus resources are reachable.
5. Press **Ctrl+C** in the window to disconnect, so routes and DNS get cleaned up. Do not just close the window.

Other options:

```powershell
# Self test: no connection, no administrator rights
.\NTUT-VPN.exe -SelfTest

# Pre-fill the username
.\NTUT-VPN.exe -VpnUser your-id

# Export this project's embedded source (supervisor, hook, worker, route helpers)
.\NTUT-VPN.exe -ExportSource .\NTUT-VPN-source.zip

# Run the PowerShell version instead of the EXE; Bypass applies to this process only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NTUT-VPN.ps1
```

The console messages are in Traditional Chinese.

## How reconnecting works

| Layer | Behavior |
|---|---|
| OpenConnect | `--reconnect-timeout=300`: reconnects the tunnel by itself for up to 5 minutes after a short outage |
| Outer supervisor | When OpenConnect exits after a connection that had succeeded, logs in again with the same credentials |

- It waits 5 seconds before reconnecting, longer after repeated failures (5 × failures seconds); Ctrl+C cancels the wait.
- A connection that stays up for 60 seconds resets the failure count; 3 failures in a row stop the tool.
- If the **first** connection fails (for example a wrong password), the tool stops instead of sending the password again and again.
- To be able to log in again, the password stays in memory as a `SecureString` while the tool runs. It is decoded only briefly when handed to OpenConnect and cleared right away, released when the tool exits, and never written to disk.

## What it changes

- While connected, it sets the VPN adapter's IP, routes and DNS as pushed by the university server, and removes them on a normal Ctrl+C disconnect.
- Each start creates a Wintun adapter named `NTUT-School-VPN-<random>`, released after disconnecting.
- While running, it unpacks OpenConnect and keeps connection state in `%TEMP%\NTUT-VPN-<GUID>\`, a folder only the current user, SYSTEM and Administrators can access. A normal exit deletes it; closing the window forcibly or a power loss can leave it behind.

## Antivirus

The executable is **not code-signed** and is a PowerShell script wrapped into an EXE, so some antivirus products may flag and quarantine it. If the file disappears or will not start, check your antivirus quarantine first. You can confirm the file is untouched with `SHA256SUMS` from the release page, use `NTUT-VPN.ps1` instead, or build it yourself.

## Troubleshooting

### The executable disappears or will not start

Most likely it was quarantined by antivirus; see "Antivirus" above. Run `NTUT-VPN.exe -SelfTest` to check that the file is intact and OpenConnect loads; the self test does not connect.

### "此登入工作階段已有北科大 VPN 工具執行中" (already running in this session)

Only one copy can run per Windows sign-in session. Stop the other VPN window (press Ctrl+C in it) and start again.

### The first connection fails and the tool stops

The tool does not retry a first connection that fails, so a wrong password is not sent again and again. Check the username and password and run it again. The error reported by OpenConnect is shown above in the window and tells whether it is a credential, certificate or network problem.

### It stops after 3 failed reconnects

Usually the university could not be reached for a while. Check that your normal internet works and run it again.

### No internet after an abnormal exit

Closing the window, a crash or a power loss skips the disconnect cleanup, which can leave VPN routes or DNS settings behind.

1. Run `NTUT-VPN.exe` again and, once connected, press **Ctrl+C** so the cleanup runs in full.
2. With the VPN not connected, check in PowerShell that nothing is left:

   ```powershell
   # These should return nothing
   Get-NetAdapter -Name 'NTUT-School-VPN*' -ErrorAction SilentlyContinue
   Get-DnsClientServerAddress -InterfaceAlias 'NTUT-School-VPN*' -ErrorAction SilentlyContinue

   # Look for 0.0.0.0/1, 128.0.0.0/1 or campus routes still pointing at a VPN adapter that no longer exists
   route print -4
   ```

3. Flush the DNS cache:

   ```powershell
   ipconfig /flushdns
   ```

4. If there is still no internet, disable and re-enable your network adapter in Network Connections, or restart Windows. VPN routes and DNS settings are not saved to the startup configuration, so a restart always clears them.

A leftover `NTUT-VPN-<GUID>` folder in `%TEMP%` can be deleted whenever the tool is not running.

## Building from source

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -SelfTest
```

This writes `dist\NTUT-VPN.ps1`, `dist\NTUT-VPN.exe` and `dist\SHA256SUMS`. The build script:

1. Checks the OpenConnect files against `vendor/openconnect-9.21/SHA256SUMS`.
2. Packs the runtime files and this project's source into two ZIPs, embeds them as Base64 into `src/NTUT-VPN.ps1`, and writes the payload's SHA-256. The same source always produces a byte-identical PS1.
3. Downloads [PS2EXE](https://github.com/MScholtes/PS2EXE) at a pinned commit, checks its SHA-256, and compiles an x64 console EXE. The EXE elevates by restarting itself.
4. With `-SelfTest`, runs the EXE's self test. Use `-SkipExe` to build only the PS1, which needs no network.

### Layout

| Path | Contents |
|---|---|
| `src/NTUT-VPN.ps1` | Main script template: elevation, unpacking, credential prompts, cleanup |
| `src/supervisor.cs` | C# supervisor that starts OpenConnect, tracks connection state and reconnects |
| `src/hook.js`, `src/route-worker.js` | OpenConnect callback and background route setup, which avoids OpenConnect's 10-second callback timeout |
| `src/vpnc-script-win.js` | Modified vpnc-script (UTF-16LE) that verifies existing routes and records routing errors |
| `src/route-helpers.js` | A standalone copy of those changes for reading |
| `vendor/openconnect-9.21/` | Executables and DLLs from the official OpenConnect v9.21 Windows CI build, unmodified |

## OpenConnect source

The files in `vendor/` come from the official Windows CI installer for the OpenConnect v9.21 tag:

```text
https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=persist-windows-builds-for-tagged-releases
SHA-256: 6EE9E8EB9BC59EF70BB0717DF7F99703F8A2CCD11D8E45D58A61F9A2E6EF7D00
```

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for component licenses.

## License

This project's own code is under the [GNU General Public License v3.0](LICENSE). `src/vpnc-script-win.js` and the third-party components in `vendor/` keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

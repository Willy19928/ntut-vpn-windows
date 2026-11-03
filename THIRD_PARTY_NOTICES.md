# Third-party notices

`NTUT-VPN.exe` and `NTUT-VPN.ps1` embed the components below. They are redistributed as separate files that are unpacked at run time; each keeps its own license.

## OpenConnect and its Windows runtime

The files in `vendor/openconnect-9.21/` are taken unmodified from the official OpenConnect v9.21 Windows CI installer:

```text
https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=persist-windows-builds-for-tagged-releases
SHA-256: 6EE9E8EB9BC59EF70BB0717DF7F99703F8A2CCD11D8E45D58A61F9A2E6EF7D00
```

| File | Component | License |
|---|---|---|
| `openconnect.exe`, `libopenconnect-5.dll` | [OpenConnect](https://gitlab.com/openconnect/openconnect) v9.21 | LGPL-2.1 |
| `libgnutls-30.dll` | [GnuTLS](https://www.gnutls.org/) | LGPL-2.1-or-later |
| `libnettle-8.dll`, `libhogweed-6.dll` | [Nettle](https://www.lysator.liu.se/~nisse/nettle/) | LGPL-3.0-or-later or GPL-2.0-or-later |
| `libgmp-10.dll` | [GMP](https://gmplib.org/) | LGPL-3.0-or-later or GPL-2.0-or-later |
| `libtasn1-6.dll` | [libtasn1](https://www.gnu.org/software/libtasn1/) | LGPL-2.1-or-later |
| `libstoken-1.dll` | [stoken](https://github.com/stoken-dev/stoken) | LGPL-2.1-or-later |
| `libintl-8.dll` | [gettext libintl](https://www.gnu.org/software/gettext/) | LGPL-2.1-or-later |
| `iconv.dll` | iconv library from the MinGW-w64 build | see upstream |
| `libxml2-2.dll` | [libxml2](https://gitlab.gnome.org/GNOME/libxml2) | MIT |
| `liblz4.dll` | [LZ4](https://github.com/lz4/lz4) | BSD-2-Clause |
| `zlib1.dll` | [zlib](https://zlib.net/) | Zlib |
| `libgcc_s_seh-1.dll` | GCC runtime | GPL-3.0-or-later with the GCC Runtime Library Exception |
| `libwinpthread-1.dll` | [MinGW-w64 winpthreads](https://www.mingw-w64.org/) | MIT and BSD-style |
| `wintun.dll` | [Wintun](https://www.wintun.net/) 0.14.1, signed by WireGuard LLC | Wintun prebuilt binaries license, which permits redistributing the unmodified DLL |

Source code for the OpenConnect build is available from the v9.21 tag of the OpenConnect repository; the Windows libraries come from the MinGW-w64 packages used by that CI job.

## vpnc-script-win.js

`src/vpnc-script-win.js` is the Windows routing script from [vpnc-scripts](https://gitlab.com/openconnect/vpnc-scripts) as shipped with OpenConnect v9.21, licensed under GPL-2.0-or-later. This project modifies it to accept a failed `route add` only when an identical route already exists, and to record the first routing error in temporary diagnostic files. The modified file is distributed under the same license; the changes are also shown in `src/route-helpers.js`.

## PS2EXE

The EXE is compiled with [PS2EXE](https://github.com/MScholtes/PS2EXE) at commit `05c62615b33864c177f5de8e56e06e4c7f34adbb`. PS2EXE is a build tool and is not included in this repository.

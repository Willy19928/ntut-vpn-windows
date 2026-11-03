# NTUT VPN for Windows

**中文** | [English](README.en.md)

在 Windows 上連線國立臺北科技大學 VPN（`vpn.ntut.edu.tw`，GlobalProtect）的單檔工具。OpenConnect 與所有依賴都包在一個 `NTUT-VPN.exe` 裡，不需要另外安裝用戶端。macOS 版見 [ntut-vpn-mac](https://github.com/Willy19928/ntut-vpn-mac)。

> 本專案是個人工具，**不是**學校官方軟體，與國立臺北科技大學無關。

## 特色

- **中斷後自動重連**：學校官方用戶端連線約 4 小時就會被強制中斷。本工具在連線中斷後會自動重新登入，不必回來重新輸入帳密。
- **單一 EXE**：內含官方 OpenConnect v9.21 Windows 版、GnuTLS 與 Wintun 驅動程式庫，下載就能用。
- **帳密不存檔**：每次啟動自己輸入帳號與密碼，密碼不會寫進命令列、設定檔或紀錄。
- **出錯不閃退**：連線失敗時視窗會停住，可以看到並複製錯誤訊息。
- 不加 Kill Switch，不修改防火牆規則；伺服器 TLS 憑證驗證維持開啟。

## 系統需求

- Windows 10／11 x64（只支援 Windows）
- Windows PowerShell 5.1（Windows 內建）
- 系統管理員權限（建立 VPN 網路介面需要，啟動時會跳出 UAC）

## 使用方式

1. 從 [Releases](https://github.com/Willy19928/ntut-vpn-windows/releases/latest) 下載 `NTUT-VPN.exe`，可用同一頁的 `SHA256SUMS` 核對。
2. 執行 `NTUT-VPN.exe`，同意 UAC。
3. 輸入 VPN 帳號與密碼（密碼輸入時不顯示）。
4. 出現連線完成訊息後即可使用校內資源。
5. 要斷線時在視窗按 **Ctrl+C**，讓程式清除路由與 DNS 設定。請不要直接關閉視窗。

其他用法：

```powershell
# 不連線、不需系統管理員權限的自我檢查
.\NTUT-VPN.exe -SelfTest

# 預先帶入帳號
.\NTUT-VPN.exe -VpnUser 帳號

# 匯出內嵌的本專案原始碼（supervisor、hook、worker、路由輔助程式）
.\NTUT-VPN.exe -ExportSource .\NTUT-VPN-source.zip

# 不使用 EXE，直接執行 PowerShell 版；Bypass 只作用於這個 PowerShell 程序
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NTUT-VPN.ps1
```

## 自動重連怎麼運作

| 層級 | 行為 |
|---|---|
| OpenConnect | `--reconnect-timeout=300`，通道短暫中斷時自行重連，最多嘗試 5 分鐘 |
| 外層監控程式 | OpenConnect 結束後，若這次曾經連線成功，就用同一組帳密重新登入 |

- 重連前等待 5 秒，連續失敗時逐次拉長（5 × 失敗次數 秒），等待期間可按 Ctrl+C 取消。
- 連線維持 60 秒以上就把失敗次數歸零；連續失敗 3 次則停止。
- **第一次連線就失敗**（例如密碼錯誤）時直接停止，不會反覆送出密碼。
- 為了能重新登入，密碼在程式執行期間以 `SecureString` 留在記憶體中，傳給 OpenConnect 時才短暫解開並立即清除；程式結束後釋放，不會寫入磁碟。

## 會修改什麼

- 連線時依學校伺服器下發的設定，替 VPN 介面設定 IP、路由與 DNS；按 Ctrl+C 正常斷線時移除。
- 每次啟動會建立名稱為 `NTUT-School-VPN-<隨機碼>` 的 Wintun 介面，斷線後釋放。
- 執行期間在 `%TEMP%\NTUT-VPN-<GUID>\` 放置解開的 OpenConnect 檔案與連線狀態檔，資料夾只有目前使用者、SYSTEM 與 Administrators 可存取；正常結束時刪除。強制關閉視窗或斷電可能留下這個資料夾。

## 防毒軟體

執行檔**未經程式碼簽章**，而且是由 PowerShell 包裝成的 EXE，部分防毒軟體可能誤判並隔離。如果執行檔消失或無法啟動，請先查看防毒軟體的隔離區。可以用 Release 頁的 `SHA256SUMS` 確認檔案沒有被竄改，或改用 `NTUT-VPN.ps1`，或自行從原始碼建置。

## 故障排除

### 執行檔消失或無法啟動

多半是被防毒軟體隔離，見上方「防毒軟體」。可以先執行 `NTUT-VPN.exe -SelfTest` 確認檔案完整、OpenConnect 能正常載入；這項檢查不會連線。

### 顯示「此登入工作階段已有北科大 VPN 工具執行中」

同一個 Windows 登入工作階段只能執行一份。先關閉另一個 VPN 視窗（在該視窗按 Ctrl+C）再啟動。

### 第一次連線就失敗後停止

第一次連線失敗時程式不會重試，避免反覆送出錯誤密碼。確認帳號與密碼正確後重新執行。視窗上方會顯示 OpenConnect 回報的錯誤，可以依錯誤內容判斷是帳密、憑證還是網路問題。

### 連續重連 3 次失敗後停止

通常是網路暫時無法連到學校。確認一般網路正常後重新執行。

### 非正常結束後無法上網

直接關閉視窗、程式當掉或斷電時，不會執行斷線清理，可能留下 VPN 的路由或 DNS 設定。

1. 重新執行 `NTUT-VPN.exe`，連上後按 **Ctrl+C** 正常斷線，讓清理流程完整跑一次。
2. 在沒有連線 VPN 時，用 PowerShell 確認已沒有殘留：

   ```powershell
   # 應該沒有任何結果
   Get-NetAdapter -Name 'NTUT-School-VPN*' -ErrorAction SilentlyContinue
   Get-DnsClientServerAddress -InterfaceAlias 'NTUT-School-VPN*' -ErrorAction SilentlyContinue

   # 檢查 0.0.0.0/1、128.0.0.0/1 或學校網段的路由是否還指向已不存在的 VPN 介面
   route print -4
   ```

3. 清除 DNS 快取：

   ```powershell
   ipconfig /flushdns
   ```

4. 仍無法上網時，到「網路連線」停用再啟用目前的網路卡，或直接重新開機。VPN 的路由與 DNS 設定不會寫入開機設定，重新開機一定會清除。

`%TEMP%` 裡留下的 `NTUT-VPN-<GUID>` 資料夾，在沒有執行本工具時可以直接刪除。

## 從原始碼建置

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 -SelfTest
```

產出 `dist\NTUT-VPN.ps1`、`dist\NTUT-VPN.exe` 與 `dist\SHA256SUMS`。建置腳本會：

1. 依 `vendor/openconnect-9.21/SHA256SUMS` 核對 OpenConnect 檔案。
2. 把執行檔案與本專案原始碼分別打包成 ZIP，以 Base64 嵌入 `src/NTUT-VPN.ps1`，並寫入套件的 SHA-256。同一份原始碼每次產生的 PS1 位元組相同。
3. 下載固定 commit 的 [PS2EXE](https://github.com/MScholtes/PS2EXE) 並比對 SHA-256，編譯成 x64 主控台 EXE。EXE 版的提升權限改為重新啟動自己。
4. 加上 `-SelfTest` 時執行 EXE 的自我檢查。只要 PS1 時可加 `-SkipExe`，不需要網路。

### 專案結構

| 路徑 | 內容 |
|---|---|
| `src/NTUT-VPN.ps1` | 主程式範本：權限、解壓、帳密輸入、清理 |
| `src/supervisor.cs` | 啟動 OpenConnect、判斷連線狀態與自動重連的 C# 監控程式 |
| `src/hook.js`、`src/route-worker.js` | OpenConnect 回呼與背景路由設定，避開 OpenConnect 回呼 10 秒逾時 |
| `src/vpnc-script-win.js` | 修改過的 vpnc-script（UTF-16LE），加入既有路由核對與錯誤診斷 |
| `src/route-helpers.js` | 上述修改的獨立副本，方便閱讀 |
| `vendor/openconnect-9.21/` | 官方 OpenConnect v9.21 Windows CI 產物中的執行檔與 DLL，未修改 |

## OpenConnect 來源

`vendor/` 內的檔案取自 OpenConnect 官方 v9.21 標籤的 Windows CI 安裝檔：

```text
https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=persist-windows-builds-for-tagged-releases
SHA-256：6EE9E8EB9BC59EF70BB0717DF7F99703F8A2CCD11D8E45D58A61F9A2E6EF7D00
```

各元件的授權見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 授權

本專案自己的程式碼採用 [GNU General Public License v3.0](LICENSE)。`src/vpnc-script-win.js` 及 `vendor/` 內的第三方元件依各自授權，見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

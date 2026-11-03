# 安全性

## 回報問題

發現安全問題時，請用 GitHub 的 [Private vulnerability reporting](https://github.com/Willy19928/ntut-vpn-windows/security/advisories/new) 私下回報，不要開公開 issue。回報時請不要附上 VPN 帳號、密碼或完整的連線紀錄。

## 設計範圍

- 密碼只在執行期間以 `SecureString` 留在記憶體，透過 stdin 交給 OpenConnect，不寫入命令列、檔案或紀錄。這可以減少暴露，但不保證密碼永遠不會出現在程序記憶體中。
- 帳號會顯示在畫面上，也會出現在 OpenConnect 子程序的命令列。
- 伺服器 TLS 憑證驗證維持開啟，沒有略過驗證的選項。
- 內嵌套件的 SHA-256 只用來確認解開的檔案與建置時相同，不是數位簽章，也不是加密。
- 執行檔未經程式碼簽章；請以 Release 頁的 `SHA256SUMS` 核對下載的檔案。

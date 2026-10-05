# devcontainer-t3code

[English](README.md) | 繁體中文

把 dev container 當成 [T3 Code](https://github.com/pingdotgg/t3code) 的環境來用：agent 在容器裡執行，由 T3 Code 桌面程式操作。容器不對外發布任何連接埠。

非官方專案，與 T3 Code 的維護者無關，也不由他們提供支援。

由兩個部分組成：

| 部分                                         | 執行位置          | 做什麼                                                                                   |
| -------------------------------------------- | ----------------- | ---------------------------------------------------------------------------------------- |
| [`t3-server`](src/t3-server/README.zh-TW.md) | dev container 裡  | 一個 dev container Feature：安裝經過雜湊驗證的 T3 Code 伺服器、啟動它，並提供只能透過 `docker exec` 進入的 SSH 入口。 |
| [`t3-dev`](host/t3-dev)                      | 執行 Docker 的主機 | 把每個這樣的容器登記成桌面程式看得到的 SSH 主機。針對「Docker 裝在 WSL、T3 Code 裝在 Windows」的情境撰寫。 |

## 快速開始

適用於 Windows，Docker 裝在 WSL 裡。

1. 在專案的 `devcontainer.json` 加上 Feature：

   ```jsonc
   "features": {
     "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
   }
   ```

2. 在 WSL 裡從最新的 release 下載 helper，讓它自己安裝。只需要做一次：

   ```bash
   curl -fsSLO https://github.com/laijunbin/devcontainer-t3code/releases/latest/download/t3-dev
   bash t3-dev setup && rm t3-dev
   ```

   想在執行前先檢查檔案，請看[驗證下載的檔案](#驗證下載的檔案)。如果手邊有這個 repo 的 checkout，執行 `host/t3-dev setup` 效果相同。之後用 `t3-dev update` 取得新版。

3. 啟動 dev container。

4. 在 T3 Code：**Settings → Connections → Add environment → SSH**，選 `t3-<資料夾名稱>`。

想讓每個專案都省略步驟 1，請看[套用到所有 dev container](src/t3-server/README.zh-TW.md#套用到所有-dev-container)。

選項、相容性、其他環境的設定方式、疑難排解與安全性說明都在 [Feature 的 README](src/t3-server/README.zh-TW.md)。

## t3-dev 指令

| 指令             | 做什麼                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| `t3-dev setup`   | 把自己複製到 `~/.local/bin`，在 Windows 使用者的 `.ssh/config` 加一行 `Include`（原檔會備份一次，存成 `config.before-t3`），並安裝一個使用者層級的 systemd 服務來執行 `t3-dev watch`。 |
| `t3-dev sync`    | 為每個裝了 Feature 的 dev container 寫一筆 SSH 主機，寫在它自己管理、放在上述設定檔旁邊的檔案裡。容器停止時主機會保留；容器被移除時主機也跟著移除。 |
| `t3-dev watch`   | 每當有容器啟動、停止或被移除就執行 `sync`。這就是那個服務在跑的東西。                                  |
| `t3-dev list`    | 顯示執行中容器的主機：主機名稱、加入 T3 Code 後顯示的名稱，以及容器 ID。加上 `-a` 會一併列出已停止的容器。除非設了 `T3_SERVER_LABEL` 或兩個專案的資料夾同名，否則兩個名稱相同。 |
| `t3-dev version` | 印出工具的版本。它和 Feature 分開編號，見[版本](#版本)。                                               |
| `t3-dev update`  | 從最新的 release 下載 `t3-dev`、檢查它（見下方）、顯示新舊版本，經你確認後取代自己；`--yes` 可跳過詢問。完成後重跑 `setup`。 |
| `t3-dev remove`  | 停止服務，並把那行 `Include` 和它自己的檔案移除。                                                      |

除此之外它不會更動 Windows 上的任何東西。`remove` 是就當下的 SSH 設定檔進行編輯，只刪掉 `setup` 加的那一行，所以這段期間你或其他工具寫進去的內容都會保留；備份檔永遠不會被還原回去。

WSL 發行版若沒有使用者層級的 systemd，`setup` 會告訴你，之後每次啟動新專案的容器後請自行執行 `t3-dev sync`。

容器是依工作區資料夾比對的，VS Code 記錄 WSL 資料夾的格式和一般的 Linux 路徑格式都認得。

每個 SSH 主機都命名為 `t3-<專案資料夾>`：轉成小寫，`a-z`、`0-9`、`-` 以外的字元都換成 `-`。Feature 預設也用這個名字稱呼環境，所以你在 **Add environment** 選的主機名稱，就是 T3 Code 之後顯示的名稱。設定 `T3_SERVER_LABEL` 只會改變 T3 Code 裡顯示的名稱；主機不變，T3 Code 存下來的環境也就不受影響。

資料夾會一直保有它拿到的主機名稱。兩個資料夾同名的專案，會依第一次出現的順序拿到 `t3-<資料夾>` 和 `t3-<資料夾>-2`，其中一個停止或啟動都不會讓另一個改變。容器被移除時（重建就會這樣），它的主機會從清單消失，但名稱仍然保留給那個資料夾：只要資料夾還在，該資料夾的下一個容器就會拿回同一個名稱。不過兩個專案在 T3 Code 裡仍然都叫 `t3-<資料夾>`，因為每個伺服器替自己命名時並不知道另一個的存在；`t3-dev list` 會指出這種情況，在其中一個專案設定 `T3_SERVER_LABEL` 就能在 T3 Code 裡區分。

### 驗證下載的檔案

`t3-dev` 不會自己連上網路；只有 `update` 會，而且只在你執行它的時候。

每個 `t3-dev` 的 release 都附有 `t3-dev`、記在 `t3-dev.sha256` 的 SHA-256，以及 `t3-dev` 的 GitHub [artifact attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations)（產物證明）。它們防範的事情不同：

| 檢查        | 能告訴你                                                                                                  | 不能告訴你                                   |
| ----------- | --------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| SHA-256     | 下載的檔案完整無損。                                                                                      | 是誰發布的：雜湊值就放在檔案旁邊。           |
| Attestation | 這個檔案確實是本 repo 的 `release.yaml` workflow 產出的，透過 Sigstore 簽署並記錄在公開的透明日誌。事後在 release 頁面被換掉的檔案會驗證失敗。 | 建置它的原始碼是否無害。請自己讀，它只是一支 shell script。 |

`update` 一定會檢查 SHA-256。若已安裝 [GitHub CLI](https://cli.github.com/) 且已登入，還會檢查 attestation，失敗就拒絕該檔案；沒有 CLI 時會說明這項檢查被略過。想手動檢查（例如第一次 `setup` 之前）：

```bash
gh attestation verify t3-dev --repo laijunbin/devcontainer-t3code \
  --signer-workflow laijunbin/devcontainer-t3code/.github/workflows/release.yaml
```

## 版本

Feature 和 `t3-dev` 各自編號、各自發布，因為更新兩者的代價差很多：

| 部分     | 版本記在                                  | 發布成                                                                       | 取得方式                                           |
| -------- | ----------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------- |
| Feature  | `src/t3-server/devcontainer-feature.json` | `ghcr.io/laijunbin/devcontainer-t3code/t3-server:<版本>`，git tag `feature_t3-server_<版本>` | 重建 dev container，會重新下載伺服器（約 70 MB）   |
| `t3-dev` | `host/t3-dev` 裡的 `T3_DEV_VERSION`       | GitHub release 與 git tag `t3-dev-v<版本>`                                   | `t3-dev update`，幾秒鐘                            |

任何版本的 `t3-dev` 都能搭配任何版本的 Feature；其中一個更新不代表另一個也要更新。只有一件事和 Feature 的版本有關：從 Feature 0.3.1 起，環境在 T3 Code 裡叫做 `t3-<資料夾>`，和主機名稱一致。容器裡若是更舊的 Feature，T3 Code 會顯示容器 ID，`t3-dev list` 也是。

## 支援範圍

盡力維護，不保證。已知可用的範圍，就是 **Test** workflow 在 x64 與 arm64 上建置並測試的那些：它的 matrix 裡的映像，以及 `test/t3-server/scenarios.json` 裡的變化組合。`t3-dev` 是在 Windows 11 搭配 WSL 2 裡的 Docker 上手動驗證的。歡迎回報其他環境的狀況，請附上映像名稱與輸出；不一定會修。

## 維護

### 支援新的 T3 Code 版本

1. 從官方 release 頁面下載 `t3-<版本>-linux-x64.tar.gz` 和 `t3-<版本>-linux-arm64.tar.gz`。
2. 對兩個檔案執行 `sha256sum`，把這兩行加進 `src/t3-server/versions.sh`。雜湊值請自己算，不要從 release 的 `SHA256SUMS` 複製；釘住雜湊的用意就是要獨立於那個檔案。
3. 更新 `version` 選項的預設值和 `proposals`、`test/t3-server/test.sh` 裡的版本，並調高 `devcontainer-feature.json` 裡 Feature 自己的 `version`。`t3-dev` 不用動。
4. Push，等 **Test** workflow 通過，再執行 **Release** workflow。

### Workflow

| Workflow    | 觸發時機                                   | 做什麼                                                                                           |
| ----------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Test**    | 每次 push 與 pull request；只改文件時不執行 | `shellcheck`，然後針對每種映像與架構建一個裝了 Feature 的容器，在裡面執行 `test/t3-server/test.sh` |
| **Release** | 手動，只能從 `main`                        | 兩個部分中，版本還沒有對應 tag 的那個才發布：把 Feature 發布到 `ghcr.io/<owner>/<repo>/<feature>` 並打 tag，以及建立 GitHub release `t3-dev-v<版本>`，附上 `t3-dev`、它的 checksum 和 attestation |

第三方 action 都釘在 commit SHA 上。發布採手動，是為了讓已發布的內容只在有意為之時才改變。只有 release 的第二個 job 能寫入 repo。

發布方式：調高有改動那一部分的版本，然後執行 **Release**。版本已經有 tag 的部分會被跳過，所以單獨發布 `t3-dev` 不會讓各專案重新下載伺服器。如果某部分的檔案變了、版本卻沒變，workflow 會停下來並指出該調高哪一個，而不是默默跳過，或用舊的版本號發布新內容。只改 Feature 資料夾裡的說明文件不算變更。

請在 repo 開啟 **Settings → General → Releases → Enable release immutability**。這樣每個 release 一經發布，GitHub 就會鎖定它的 tag 和檔案，連擁有者的帳號事後都換不掉。

第一次發布會建立私有的 package。請到 GitHub 上該 package 的設定頁，把可見性改成 public。

### 檔案配置

```
src/t3-server/
  devcontainer-feature.json   中繼資料、選項、volume、entrypoint
  install.sh                  建置映像時的安裝程序（以 root 執行）
  versions.sh                 釘住的壓縮檔雜湊
  scripts/entrypoint.sh       容器啟動時啟動伺服器
  scripts/t3-server           status / start / stop / restart / logs
  scripts/ssh-session         透過 docker exec 提供一次 SSH 連線
  scripts/t3-pair             配對連結小工具，供發布連接埠的做法使用
  README.md                   使用者文件（README.zh-TW.md 為繁體中文版）
host/t3-dev                   主機端的 helper（WSL）
test/t3-server/test.sh        `devcontainer features test` 執行的檢查
test/t3-server/scenarios.json 額外要測的映像與選項組合
```

# T3 Code 伺服器（`t3-server`）

[English](README.md) | 繁體中文

在 dev container 裡執行 [T3 Code](https://github.com/pingdotgg/t3code) 伺服器，讓 T3 Code 桌面程式能把這個容器當成環境使用。agent 因此在容器內工作，享有容器原本就給專案的隔離。

容器不發布任何連接埠。桌面程式透過由 `docker exec` 承載的 SSH 連到伺服器，並直接沿用 Feature 已經啟動的那個伺服器。

這是非官方的社群 Feature，與 T3 Code 的維護者無關，也不由他們提供支援。

## 用法

```jsonc
{
  "features": {
    "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
  }
}
```

專案這邊要改的就只有這樣。dev container 需要有非 root 的 `remoteUser`，以及 provider 的 CLI（見 [Providers](#providers)）。

在執行 Docker 的那台機器上，要讓桌面程式的 `ssh` 有辦法進到容器。如果是「Docker 裝在 WSL、T3 Code 裝在 Windows」，這個 repo 裡的 [`t3-dev`](../../host/t3-dev) helper 會處理（[取得方式](../../README.zh-TW.md#快速開始)）：

```bash
t3-dev setup    # 只需一次
```

之後主機清單會自動跟著你的容器變動。WSL 發行版若沒有使用者層級的 systemd，啟動新專案的容器後請執行 `t3-dev sync`。

接著在 T3 Code：**Settings → Connections → Add environment → SSH**，選 `t3-<資料夾名稱>`。

其他環境請看[不使用 helper 連線](#不使用-helper-連線)。

## 選項

| 選項        | 預設值      | 意義                                                                                                 |
| ----------- | ----------- | ---------------------------------------------------------------------------------------------------- |
| `version`   | `0.0.45`    | 要安裝的 T3 Code 版本。必須在 `versions.sh` 裡有釘住的雜湊。                                         |
| `autostart` | `true`      | 每次容器啟動時都啟動伺服器。                                                                         |
| `ssh`       | `true`      | 安裝只能經由 `docker exec` 使用的 SSH 入口。會把 remote user 的密碼清空（見[安全性說明](#安全性說明)）。 |
| `host`      | `127.0.0.1` | 伺服器在容器內監聽的位址。`0.0.0.0` 只用於[改用發布連接埠](#改用發布連接埠)的做法。                  |
| `strict`    | `true`      | 映像無法執行這個 Feature 時讓建置失敗。設為 `false` 則改為略過 Feature（見[套用到所有 dev container](#套用到所有-dev-container)）。 |

`T3CODE_PORT`（預設 `3773`）和 `T3CODE_TELEMETRY_ENABLED`（預設 `false`）可以透過專案的 `containerEnv` 覆寫。`T3_SERVER_LABEL` 也可以，它是 T3 Code 顯示的環境名稱；預設是 `t3-<專案資料夾>`。

## 容器內的指令

| 指令                         | 用途                                                                       |
| ---------------------------- | -------------------------------------------------------------------------- |
| `t3-server status`           | 是否在執行且有回應？兩者皆是，結束代碼才會是 0。                           |
| `t3-server start`            | 啟動並等到它有回應（最多 60 秒）。                                         |
| `t3-server stop` / `restart` | 停止或重新啟動。                                                           |
| `t3-server logs [-n N]`      | 顯示 log，其中的配對機密會被濾掉。                                         |
| `t3-server label`            | 印出 T3 Code 顯示的這個環境的名稱。                                        |
| `t3-pair [PORT\|ORIGIN]`     | 產生配對連結；只有[改用發布連接埠](#改用發布連接埠)時才需要。              |

這些指令可以用伺服器的使用者或 root 執行；用 root 執行時會自動降為伺服器的使用者。

## 這個 Feature 做了什麼

- **建置映像時：** 從官方的 GitHub release 下載壓縮檔，和這個 Feature 裡釘住的 SHA-256 比對，然後安裝到 `/opt/t3-server`。容器啟動時不會下載任何東西。
- **資料：** thread、歷史紀錄和配對狀態存放在每個 dev container 專屬的具名 volume，掛載在 `/var/lib/t3-server`，權限 `0700`。remote user 的 `~/.t3` 會連結到它。
- **啟動：** Feature 的 entrypoint 在背景啟動伺服器，不拖慢容器啟動。伺服器從 `/` 啟動、以 remote user 身分執行、關閉產品遙測，並只監聽 loopback。
- **名稱：** T3 Code 原本會把容器 ID 當成環境名稱。Feature 改寫成 `t3-<資料夾>`，寫在 `/etc/machine-info` 的 `PRETTY_HOSTNAME`，T3 Code 會優先採用它。資料夾指的是掛載在 `/workspaces/<資料夾>` 的那個，轉成小寫，`a-z`、`0-9`、`-` 以外的字元都換成 `-`。`t3-dev` 也用同樣的方式由資料夾替 SSH 主機命名，所以新增環境時選的名稱，就是之後顯示的名稱。已經存在、且不是 Feature 寫的 `/etc/machine-info` 不會被更動。`t3-server label` 會印出目前使用的名稱。
- **SSH 入口：** `/usr/local/share/t3-server/ssh-session` 透過標準輸入輸出提供一次 SSH 連線。不會有 SSH daemon 在執行，也不開任何連接埠。它的 host key 存在資料 volume 裡，並使用自己的設定檔；映像原本的系統 SSH 設定不會被更動。
- **讓用戶端沿用：** T3 Code 的 SSH 模式會在 `~/.t3` 尋找執行中的伺服器，以及與自己同版本的已安裝 runtime。兩者它都找得到，所以既不會啟動第二個伺服器，也不會再下載一份。

為什麼由 Feature 啟動伺服器，而不是交給用戶端：伺服器只會提供「它啟動時所在目錄」底下的 diff。用戶端是從家目錄啟動的，這會讓 `/workspaces` 底下專案的 Diff 面板一片空白。Feature 則從 `/` 啟動。

它不會安裝或登入 provider、不會保存 provider 的登入、不會更新伺服器，也不會在伺服器當掉後重新啟動它。

## 相容性

### 映像

| 需求     | 細節                                                                                                     |
| -------- | -------------------------------------------------------------------------------------------------------- |
| C 函式庫 | glibc。Alpine 等使用 musl 的映像會在建置時被拒絕，因為 T3 Code 沒有發布 musl 版本。                      |
| 架構     | x64 與 arm64，也就是 T3 Code 發布的兩種 Linux 版本。                                                     |
| 使用者   | 開啟 `ssh` 時需要非 root 的 `remoteUser`。                                                               |
| 套件     | `curl` 或 `wget`、`tar`、`gzip`、`sha256sum`、`bash`、CA 憑證、`libatomic`、`runuser` 或 `setpriv`；使用 `ssh` 時另需 OpenSSH server 和 `passwd`。 |

缺少的套件在使用 apt 的映像（Debian、Ubuntu）和使用 dnf 的映像（Fedora、RHEL 系列）上會自動安裝。其他映像則會停止建置，並列出需要加進基底映像的東西。slim 映像可以用。

這個 repo 的 **Test** workflow 會在 x64 與 arm64 的 runner 上，針對它 matrix 裡的映像和 `test/t3-server/scenarios.json` 裡的變化組合，建置裝了 Feature 的容器並執行測試。這些就是已知可用的環境；要依賴不在其中的環境之前，請先看最近一次的執行結果。

remote user 的 UID 可能和映像裡的不同：dev container 工具會把它改成和主機使用者一致。資料 volume 的擁有者會在容器啟動時修正：entrypoint 以 root 執行時直接修正，否則透過免密碼的 `sudo`。

### Dev container 工具

伺服器是由 Feature 的 `entrypoint` 啟動的，而 Dev Containers 規範把是否執行它留給各個工具決定。VS Code 會執行。如果容器剛啟動後 `t3-server status` 顯示「not running」，代表你的工具沒有執行它；請在專案加上：

```jsonc
"postStartCommand": "t3-server start"
```

這個指令可以重複執行而不出問題，所以即使 entrypoint 有作用，留著也無妨。

### T3 Code 用戶端版本

桌面程式會自動更新；容器裡的伺服器只在你改 `version` 選項時才會變。用戶端會沿用任何已在執行的伺服器，所以較新的用戶端會透過 T3 Code 的功能協商和較舊的伺服器溝通。這個 Feature 只和相同版本的用戶端一起測試過。

## Providers

T3 Code 操作的是 provider 的 CLI，它們必須已經在容器裡，而且在容器啟動時的 `PATH` 上。Claude Code 可以用官方的 Feature：

```jsonc
"features": {
  "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": {}
}
```

照平常的方式在容器裡登入即可。登入能否撐過容器重建，取決於專案自己的掛載設定；這個 Feature 不碰 provider 的憑證。

## 套用到所有 dev container

VS Code 可以把某個 Feature 加到你開啟的每一個 dev container，完全不用改專案。在使用者設定裡：

```jsonc
"dev.containers.defaultFeatures": {
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": { "strict": false }
}
```

這裡請保留 `"strict": false`。套用到所有容器時，Feature 一定會遇到它無法支援的映像：Alpine、只有 root 的映像、沒有套件管理工具的映像。關掉 `strict` 後，它會印出原因且什麼都不安裝，容器就照沒有它的樣子建置完成。雜湊不符或 `version` 不存在時，建置仍然會失敗。

需要知道的事：

- 這是 VS Code 的設定。`devcontainer` CLI 和其他工具不會理會它。
- provider 的 CLI 仍然是專案或你自己的事；想要到處都有，就把它的 Feature 加進同一個設定。
- 如果專案有 `devcontainer-lock.json`，VS Code 可能會把你的預設 Feature 記進去。commit 那個檔案前請先檢查。
- 容器要到下一次重建時才會套用這個 Feature。

## 不使用 helper 連線

任何能在 Docker 主機上執行 `docker exec` 的東西都能承載這條連線。SSH 用戶端設定裡，每個容器需要這樣一段：

```
Host t3-myproject
    User vscode
    ProxyCommand docker exec -i -u root <container> /usr/local/share/t3-server/ssh-session
    PubkeyAuthentication no
```

`User` 是 dev container 的 remote user。在 Windows 搭配 WSL 裡的 Docker 時，請在指令前面加上 `wsl.exe -d <distro> --`。`t3-dev` 寫的正是這種設定，而且它是依工作區資料夾找容器，所以容器重建後設定依然有效。

## 改用發布連接埠

不使用 SSH 時，可以發布伺服器的連接埠並手動配對：

```jsonc
"features": { "ghcr.io/laijunbin/devcontainer-t3code/t3-server:0": { "host": "0.0.0.0", "ssh": false } },
"runArgs": ["-p", "127.0.0.1:38101:3773"]
```

在容器裡執行 `t3-pair 38101`，把連結貼到 **Add environment**。請保留 `127.0.0.1:` 這個前綴，並讓每個專案使用各自的主機連接埠。在 Windows 上用 VS Code 搭配 WSL 裡的 Docker 時，VS Code 可能會在 Windows 這一側占用那個已發布的連接埠，視窗關閉後還繼續占著；SSH 的做法沒有這個問題。

## 疑難排解

| 症狀                                              | 原因與處理方式                                                                                                                                       |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 建置失敗，訊息為 `has no pinned hash`             | 指定的 `version` 不在 `versions.sh` 裡。請用清單裡的版本，或自行加入雜湊（見 repo 的 README）。                                                      |
| 建置長時間停在 `downloading t3-…`                 | 伺服器壓縮檔約 70 MB，來自 GitHub 的 release 儲存空間，有時會很慢。建置 log 每 20 秒印一次 `downloaded N MB so far`；停止傳輸的連線會被中斷並重試，試了幾次仍失敗才會讓建置報錯，不會無限期卡住。每個 Feature 版本、每個專案映像只會發生一次。 |
| 建置失敗，訊息為 `hash mismatch`                  | 下載到的壓縮檔不是這個 Feature 釘住的那一個。不要想辦法繞過；請檢查該 release 並回報。                                                               |
| 建置失敗，訊息為 `does not use glibc`             | 基底映像使用 musl。請改用 glibc 的映像。                                                                                                             |
| 建置失敗，訊息為 `needs a non-root remoteUser`    | 在 `devcontainer.json` 設定 `remoteUser`，或使用 `"ssh": false`。                                                                                    |
| 建置失敗，訊息為 `~/.t3 already exists`           | 有別的東西提供了 `~/.t3`（某個掛載，或映像裡的檔案）。請移除它；Feature 會把這個路徑連結到自己的 volume。                                            |
| `t3-server status`：啟動後仍是 not running        | 見 [Dev container 工具](#dev-container-工具)。                                                                                                       |
| `t3-server start`：`is not writable`              | 資料 volume 屬於另一個 UID 而且無法修正；修正需要 root 或免密碼的 `sudo`。請以 root 執行一次 `t3-server start`（`docker exec -u root <container> t3-server start`）。 |
| `t3-dev sync` 沒有列出任何東西                    | 容器沒在執行、建置時沒有這個 Feature、設了 `"ssh": false`，或 Feature 自行略過了（`"strict": false`；建置 log 會說明原因）。                         |
| SSH：`no running dev container for ...`           | 容器已停止。啟動它即可，不需要重新 sync。                                                                                                            |
| SSH：host key changed                             | 資料 volume 被重新建立了。執行 `t3-dev sync`，它會清掉舊的 key。                                                                                     |
| `git status` 看得到變更，Diff 面板卻沒有          | 回應的是另一個由用戶端從家目錄啟動的伺服器。執行 `t3-server status`；如果 Feature 的伺服器沒在執行，啟動它後重新連線。                               |
| 環境名稱是容器 ID                                 | 專案不是掛載在 `/workspaces` 底下，或映像有自己的 `/etc/machine-info`。在 `containerEnv` 設定 `T3_SERVER_LABEL`，然後執行 `t3-server restart`。      |
| provider 顯示為未安裝                             | 它的 CLI 不在伺服器的 `PATH` 上。安裝後執行 `t3-server restart`；伺服器是在啟動時讀取 `PATH` 的。                                                    |

## 安全性說明

- **釘住的雜湊。** 官方安裝程式是拿壓縮檔和同一個 release 裡的 checksum 檔比對。這個 Feature 則是和 commit 在本 repo 裡的雜湊比對，所以 release 事後若被替換，建置會失敗而不是照裝。沒有任何選項可以跳過這項檢查。
- **沒有對外的監聽面。** 伺服器只監聽容器內的 loopback，沒有發布任何東西。其他容器和主機都連不到它；唯一的入口是 `docker exec`。
- **免密碼的 SSH，以及原因。** SSH 入口不需要金鑰或密碼就接受 remote user。它只能經由 `docker exec` 到達，而 `docker exec` 本來就能完整存取容器，所以加上金鑰也擋不住任何人。為了讓這行得通，Feature 會清空 remote user 的密碼。映像的系統 SSH 設定仍保持 `PermitEmptyPasswords` 的預設值 `no`，所以你自己執行的 SSH daemon 依然會拒絕這種登入。不要讓其他 SSH daemon 使用 `/usr/local/share/t3-server/sshd_config`，也不要對它發布連接埠。
- **原始 log 含有管理用的配對 token**，是啟動時留下的，同時以文字和 QR code 的形式出現。該檔案位於資料 volume，權限 `0600`，而 `t3-server logs` 會把這些全部濾掉。不要分享原始檔案。
- **預設的權限模式。** T3 Code 的新 thread 預設是 Full access。每個環境有各自的設定，所以每新增一個環境都要去改預設值。
- **容器邊界給你的保障。** agent 讀得到容器裡的一切，包括掛載進來的 provider 登入。除非專案自己把主機的檔案或 Docker 掛進來，否則 agent 碰不到它們。

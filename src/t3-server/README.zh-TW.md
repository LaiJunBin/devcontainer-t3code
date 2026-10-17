# 透過 SSH 使用的 T3 Code 環境（`t3-server`）

[English](README.md) | 繁體中文

把 dev container 變成 [T3 Code](https://github.com/pingdotgg/t3code) 的環境，讓 T3 Code 桌面程式能在容器裡執行 agent，享有容器原本就給專案的隔離。

容器不發布任何連接埠。桌面程式透過由 `docker exec` 承載的 SSH 進到容器，然後在裡面安裝並啟動和它自己同版本的 T3 Code 伺服器。桌面程式更新後，下次連線時會自動換掉那個伺服器，所以 T3 Code 改版時，這個 Feature 不必跟著改。

這是非官方的社群 Feature，與 T3 Code 的維護者無關，也不由他們提供支援。

## 用法

```jsonc
{
  "features": {
    "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": {}
  }
}
```

專案這邊要改的就只有這樣。dev container 需要有非 root 的 `remoteUser`，以及 provider 的 CLI（見 [Providers](#providers)）。請使用 0.1.0 以上的 T3 Code 桌面程式（見 [T3 Code 版本](#t3-code-版本)）。

在執行 Docker 的那台機器上，要讓桌面程式的 `ssh` 有辦法進到容器。如果是「Docker 裝在 WSL、T3 Code 裝在 Windows」，這個 repo 裡的 [`t3-dev`](../../host/t3-dev) helper 會處理（[取得方式](../../README.zh-TW.md#快速開始)）：

```bash
t3-dev setup    # 只需一次
```

之後主機清單會自動跟著你的容器變動。WSL 發行版若沒有使用者層級的 systemd，啟動新專案的容器後請執行 `t3-dev sync`。

接著在 T3 Code：**Settings → Connections → Add environment → SSH**，選 `t3-<資料夾名稱>`。第一次連到某個容器時，桌面程式會把伺服器（約 90 MB）下載到容器的資料 volume；之後的連線和容器重建都會沿用它，直到桌面程式更新為止。

其他環境請看[不使用 helper 連線](#不使用-helper-連線)。想從手機使用這些專案，請看[手機存取](../../README.zh-TW.md#手機存取)。

## 選項

| 選項     | 預設值 | 意義 |
| -------- | ------ | ---- |
| `strict` | `true` | 映像無法使用這個 Feature 時讓建置失敗。設為 `false` 則改為略過 Feature（見[套用到所有 dev container](#套用到所有-dev-container)）。 |

在專案的 `containerEnv` 設定 `T3_SERVER_LABEL`，可以指定 T3 Code 顯示的環境名稱；預設是 `t3-<專案資料夾>`。T3 Code 是在加入環境的當下把名稱存起來的，所以改了之後要先重建容器，再到 T3 Code 把該環境移除，用同一個主機重新加入。

桌面程式用來啟動伺服器的 SSH 連線裡，`T3CODE_TELEMETRY_ENABLED` 是 `false`。在 `containerEnv` 設定它可以覆寫這個值。

## 容器內的指令

| 指令                    | 用途 |
| ----------------------- | ---- |
| `t3-server status`      | 伺服器是否在執行、版本、使用的名稱。在執行且有回應時結束代碼才是 0；沒有在執行時是 3。 |
| `t3-server stop`        | 停止伺服器。桌面程式下次連線時會啟動新的。 |
| `t3-server logs [-n N]` | 顯示伺服器的 log，其中的配對機密會被濾掉。 |
| `t3-server label`       | 印出 T3 Code 顯示的這個環境的名稱。 |

這些指令可以用 remote user 或 root 執行；用 root 執行時會自動降為 remote user。`t3-server start` 和 `restart` 什麼都不做、直接回傳成功：伺服器由桌面程式負責啟動，保留這兩個指令只是為了讓為 0.x 寫的 `postStartCommand` 繼續正常運作。

## 這個 Feature 做了什麼

- **SSH 入口：** `/usr/local/share/t3-server/ssh-session` 透過標準輸入輸出提供一次 SSH 連線。不會有 SSH daemon 在執行，也不開任何連接埠。它的 host key 存在資料 volume 裡，並使用自己的設定檔；映像原本的系統 SSH 設定不會被更動。
- **SSH 連線裡的容器環境：** SSH 登入會從乾淨的環境開始，`/etc/profile` 又會重設 `PATH`。桌面程式是從這樣的登入 shell 啟動伺服器的，所以 `ssh-session` 會把 `docker exec` 交給它的環境（也就是容器的環境）存下來，再由 `/etc/profile.d/t3-server-ssh-env.sh` 在那次連線的登入 shell 裡還原。伺服器因此看得到容器裡其他程序看得到的東西：其他 Feature 加進 `PATH` 的工具，以及 `CLAUDE_CONFIG_DIR` 這類變數。只有經由這個入口的連線會受影響。
- **資料：** 每個 dev container 專屬的具名 volume，掛載在 `/var/lib/t3-server`，權限 `0700`，remote user 的 `~/.t3` 連結到它。裡面放著桌面程式下載的伺服器、thread、歷史紀錄、設定和配對狀態，所以容器重建後都還在。
- **名稱：** T3 Code 原本會把容器 ID 當成環境名稱。Feature 改寫成 `t3-<資料夾>`，寫在 `/etc/machine-info` 的 `PRETTY_HOSTNAME`，T3 Code 會優先採用它。資料夾指的是掛載在 `/workspaces/<資料夾>` 的那個，轉成小寫，`a-z`、`0-9`、`-` 以外的字元都換成 `-`。`t3-dev` 也用同樣的方式由資料夾替 SSH 主機命名，所以新增環境時選的名稱，就是之後顯示的名稱。已經存在、且不是 Feature 寫的 `/etc/machine-info` 不會被更動。
- **桌面程式的安裝程序需要的工具：** 缺少 `curl` 或 `wget`、`tar`、`gzip`、`sha256sum`、CA 憑證、`libatomic` 時會自動安裝。

容器在執行時，伺服器就會一直執行，桌面程式斷線後也一樣。容器重啟後，要等桌面程式下次連線才會再啟動；在那之前什麼都不會執行，排程任務也是。

它不會安裝或登入 provider，也不會保存 provider 的登入。

### 從 0.x（`:0`）升級

到 0.3 為止，Feature 會把一個固定版本的 T3 Code 裝進映像，並隨容器啟動。這讓所有專案都綁在同一個版本上：桌面程式更新後會拒絕連線到舊版伺服器，要等 Feature 更新、所有容器重建才能恢復。1.0.0 把伺服器交給桌面程式負責。

`:0` 標籤會停在 0.3，只要桌面程式維持 0.0.45 就照常運作。要換過來，把引用改成 `t3-server:1`（在 `devcontainer.json` 或 `dev.containers.defaultFeatures` 裡），然後重建。換之前請先確認這些變化：

- **請使用 0.1.0 以上的桌面程式。** 較舊的桌面程式也能連線並安裝自己的伺服器，但那個伺服器只顯示家目錄底下的 diff，`/workspaces` 底下專案的 Diff 面板會是空的。0.3 是靠從 `/` 啟動伺服器避開這個問題。
- **需要非 root 的 `remoteUser`。** 先前搭配 `"ssh": false` 使用的純 root 映像會建置失敗，設了 `"strict": false` 則會被略過。
- **發布連接埠的做法已移除**，連同 `t3-pair` 和 `ssh: false` 的設定。請改用 SSH 入口。
- `version`、`autostart`、`ssh`、`host` 這幾個選項已移除；建置時若仍設定了它們，會印出提示並繼續。
- `t3-server start` 和 `restart` 不再啟動任何東西，但仍回傳成功，所以呼叫它們的 `postStartCommand` 不會造成問題，可以移除。
- 桌面程式連線之前，容器裡什麼都不會執行，排程任務也是。
- 重建後第一次啟動時，會刪除 0.3 留下的伺服器 log（裡面有配對 token）和 runtime 連結。資料 volume 裡的 thread 和設定都會保留。第一次連線時會下載桌面程式對應版本的伺服器；T3 Code 0.1 第一次啟動時，會把先前的 thread 複製到新的資料庫。

## 相容性

### 映像

| 需求     | 細節 |
| -------- | ---- |
| C 函式庫 | glibc。Alpine 等使用 musl 的映像會在建置時被拒絕，因為 T3 Code 沒有發布 musl 版本。 |
| 架構     | x64 與 arm64，也就是 T3 Code 發布的兩種 Linux 版本。 |
| 使用者   | 非 root 的 `remoteUser`。 |
| 套件     | `curl` 或 `wget`、`tar`、`gzip`、`sha256sum`、`bash`、CA 憑證、`libatomic`、`runuser` 或 `setpriv`、OpenSSH server 和 `passwd`。 |

缺少的套件在使用 apt 的映像（Debian、Ubuntu）和使用 dnf 的映像（Fedora、RHEL 系列）上會自動安裝。其他映像則會停止建置，並列出需要加進基底映像的東西。slim 映像可以用。

這個 repo 的 **Test** workflow 會在 x64 與 arm64 的 runner 上，針對它 matrix 裡的映像和 `test/t3-server/scenarios.json` 裡的變化組合，建置裝了 Feature 的容器並執行測試。其中一個情境會照桌面程式的做法，經由 SSH 入口安裝並啟動真正的 T3 Code 伺服器。這些就是已知可用的環境；要依賴不在其中的環境之前，請先看最近一次的執行結果。

remote user 的 UID 可能和映像裡的不同：dev container 工具會把它改成和主機使用者一致。資料 volume 的擁有者會在容器啟動時修正（entrypoint 以 root 執行時直接修正，否則透過免密碼的 `sudo`），每次 SSH 連線開始時也會再修正一次。

### Dev container 工具

Feature 的 `entrypoint` 會在容器啟動時設定環境名稱並修正 volume。Dev Containers 規範把是否執行它留給各個工具決定，VS Code 會執行。不執行它的工具，SSH 入口會在桌面程式連線時做同樣的事。

### T3 Code 版本

伺服器一律來自桌面程式本身，所以桌面程式和伺服器永遠是同一個版本，T3 Code 更新時這裡也不需要任何改動。

請使用 0.1.0 以上的桌面程式。較舊的版本也能連線，但它們的伺服器只顯示啟動目錄（家目錄）底下的 diff，`/workspaces` 底下專案的 Diff 面板會是空的。0.1.0 起，伺服器也會顯示所有已登錄專案的 diff。

## Providers

T3 Code 操作的是 provider 的 CLI，它們必須在容器裡。Claude Code 可以用官方的 Feature：

```jsonc
"features": {
  "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": {}
}
```

照平常的方式在容器裡登入即可。登入能否撐過容器重建，取決於專案自己的掛載設定；這個 Feature 不碰 provider 的憑證。CLI 從容器環境需要的東西都會傳到伺服器（見[這個 Feature 做了什麼](#這個-feature-做了什麼)）；只透過 VS Code 的 `remoteEnv` 設定的值則不會，因為它們只存在於 VS Code 自己的程序裡。

## 套用到所有 dev container

VS Code 可以把某個 Feature 加到你開啟的每一個 dev container，完全不用改專案。在使用者設定裡：

```jsonc
"dev.containers.defaultFeatures": {
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": { "strict": false }
}
```

這裡請保留 `"strict": false`。套用到所有容器時，Feature 一定會遇到它無法支援的映像：Alpine、只有 root 的映像、沒有套件管理工具的映像。關掉 `strict` 後，它會印出原因且什麼都不安裝，容器就照沒有它的樣子建置完成。

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

## 疑難排解

| 症狀 | 原因與處理方式 |
| ---- | -------------- |
| 建置失敗，訊息為 `does not use glibc` | 基底映像使用 musl。請改用 glibc 的映像。 |
| 建置失敗，訊息為 `needs a non-root remoteUser` | 在 `devcontainer.json` 設定 `remoteUser`。 |
| 建置失敗，訊息為 `~/.t3 already exists` | 有別的東西提供了 `~/.t3`（某個掛載，或映像裡的檔案）。請移除它；Feature 會把這個路徑連結到自己的 volume。 |
| 第一次連線很久 | 桌面程式正在把伺服器（約 90 MB）下載到容器裡。每個容器在每個桌面程式版本只會發生一次。 |
| `t3-server status`：not running | 容器啟動後桌面程式還沒連線過。在 T3 Code 連到這個環境即可。 |
| `t3-server`：`is not writable` | 資料 volume 屬於另一個 UID 而且無法修正；修正需要 root 或免密碼的 `sudo`。請執行 `docker exec -u root <container> t3-server prepare`。 |
| `t3-dev sync` 沒有列出任何東西 | 容器沒在執行、建置時沒有這個 Feature，或 Feature 自行略過了（`"strict": false`；建置 log 會說明原因）。 |
| SSH：`no running dev container for ...` | 容器已停止。啟動它即可，不需要重新 sync。 |
| SSH：host key changed | 資料 volume 被重新建立了。執行 `t3-dev sync`，它會清掉舊的 key。 |
| provider 顯示為未安裝 | 伺服器啟動時容器裡還沒有它的 CLI。執行 `t3-server stop`，再到 T3 Code 重新連線。 |
| 環境名稱是容器 ID | 專案不是掛載在 `/workspaces/<資料夾>`（Docker Compose 通常如此），Feature 無法得知資料夾名稱。`t3-dev sync` 會替它命名。沒有使用 `t3-dev`，或映像有自己的 `/etc/machine-info` 時，請在 `containerEnv` 設定 `T3_SERVER_LABEL` 並重建。若伺服器當時已在執行，先執行 `t3-server stop` 再重新連線；之後到 T3 Code 移除該環境並重新加入。 |
| 改了 `T3_SERVER_LABEL`，T3 Code 仍顯示舊名稱 | T3 Code 會保留加入環境當下取得的名稱。到 **Settings → Connections** 移除該環境，再用同一個主機加入一次；thread 存在容器的資料 volume 裡，不會消失。 |
| 新增環境時取代了另一個環境，或出現 `[ssh_http:401]` | 這個 SSH 主機現在通往的容器，和 T3 Code 第一次連它時不同，而程式還握著舊的連線。請完全結束 T3 Code 再重新開啟，用 `t3-dev list` 核對主機與資料夾，然後再加入環境。 |

## 安全性說明

- **伺服器的來源。** 桌面程式從 T3 Code 的 GitHub release 下載伺服器，並和同一個 release 裡的 `SHA256SUMS` 比對。這能發現下載損壞，但防不了整個 release 被替換；桌面程式本身也是從同一處下載的。到 0.3（`:0`）為止，這個 Feature 改用本 repo 裡釘住的雜湊，代價是所有專案都綁在同一個版本上。
- **沒有對外的監聽面。** 伺服器只監聽容器內的 loopback，沒有發布任何東西。其他容器和主機都連不到它；唯一的入口是 `docker exec`。`t3-dev` 的[手機存取](../../README.zh-TW.md#手機存取)開啟時，就是經由這個入口把伺服器轉送給你的 Tailscale 裝置。
- **免密碼的 SSH，以及原因。** SSH 入口不需要金鑰或密碼就接受 remote user。它只能經由 `docker exec` 到達，而 `docker exec` 本來就能完整存取容器，所以加上金鑰也擋不住任何人。為了讓這行得通，Feature 會清空 remote user 的密碼。映像的系統 SSH 設定仍保持 `PermitEmptyPasswords` 的預設值 `no`，所以你自己執行的 SSH daemon 依然會拒絕這種登入。不要讓其他 SSH daemon 使用 `/usr/local/share/t3-server/sshd_config`，也不要對它發布連接埠。
- **存下來的環境。** 容器的環境可能包含透過 `containerEnv` 設定的憑證，它會為 SSH 連線存在 `/run/t3-server/session-env`，只有 remote user 讀得到。該使用者的程序讀得到它，就像它們讀得到自己的環境一樣。
- **原始的伺服器 log 可能含有管理用的配對 token。** `t3-server logs` 會把它濾掉。不要分享 `~/.t3/ssh-launch/` 底下的原始檔案。
- **預設的權限模式。** T3 Code 的新 thread 預設是 Full access。每個環境有各自的設定，所以每新增一個環境都要去改預設值。
- **容器邊界給你的保障。** agent 讀得到容器裡的一切，包括掛載進來的 provider 登入。除非專案自己把主機的檔案或 Docker 掛進來，否則 agent 碰不到它們。

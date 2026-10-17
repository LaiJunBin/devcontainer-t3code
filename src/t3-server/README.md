# T3 Code environment over SSH (`t3-server`)

English | [繁體中文](README.zh-TW.md)

Makes a dev container a [T3 Code](https://github.com/pingdotgg/t3code) environment, so the T3 Code desktop app can run its agents inside the container, with the isolation the container already gives the project.

The container publishes no port. The desktop app reaches it over SSH carried by `docker exec`, then installs and starts a T3 Code server of its own version there. When the app updates, it replaces that server the next time it connects, so this feature does not have to change when T3 Code does.

This is an unofficial, community feature. It is not affiliated with or supported by the T3 Code maintainers.

## Usage

```jsonc
{
  "features": {
    "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": {}
  }
}
```

That is the whole project-side change. The dev container needs a non-root `remoteUser`, and a provider CLI (see [Providers](#providers)). Use the T3 Code desktop app 0.1.0 or later (see [T3 Code versions](#t3-code-versions)).

On the machine that runs Docker, give the desktop app's `ssh` a way into the container. For Docker inside WSL with T3 Code on Windows, the [`t3-dev`](../../host/t3-dev) helper in this repository does it ([how to get it](../../README.md#quick-start-windows-docker-in-wsl)):

```bash
t3-dev setup    # once
```

From then on the list of hosts follows your containers by itself. Where the WSL distro has no user-level systemd, run `t3-dev sync` after starting a new project's container.

Then in T3 Code: **Settings → Connections → Add environment → SSH**, and pick `t3-<folder name>`. The first connection to a container downloads the server (about 90 MB) into the container's data volume; later connections and rebuilds reuse it until the app updates.

For other setups, see [Connecting without the helper](#connecting-without-the-helper).

## Options

| Option   | Default | Meaning |
| -------- | ------- | ------- |
| `strict` | `true`  | Fail the build when the image cannot run the feature. `false` skips the feature instead (see [For every dev container](#for-every-dev-container)). |

`T3_SERVER_LABEL` in the project's `containerEnv` sets the name T3 Code shows for the environment; by default it is `t3-<project folder>`. T3 Code stores the name when the environment is added, so after changing it, rebuild the container, then remove the environment in T3 Code and add the same host again.

`T3CODE_TELEMETRY_ENABLED` is `false` in the SSH sessions the app starts its server from. A `containerEnv` value replaces that.

## Commands in the container

| Command                 | Purpose |
| ----------------------- | ------- |
| `t3-server status`      | Is a server running, which version, and under what name. Exit code 0 only if it runs and answers; 3 if none runs. |
| `t3-server stop`        | Stop it. The app starts a new one the next time it connects. |
| `t3-server logs [-n N]` | Show the server's log with pairing secrets removed. |
| `t3-server label`       | Print the name T3 Code shows for this environment. |

They can be run as the remote user or as root; root drops to the remote user. `t3-server start` and `restart` do nothing and succeed: the server is the app's to start, and they stay only so that a `postStartCommand` written for 0.x keeps working.

## What the feature does

- **SSH entry point:** `/usr/local/share/t3-server/ssh-session` serves one SSH session over stdin/stdout. No SSH daemon runs and no port is opened. Its host key is kept in the data volume, and it uses its own configuration file; the image's system SSH configuration is not changed.
- **The container's environment in SSH sessions:** an SSH login starts from a clean environment, and `/etc/profile` then resets `PATH`. Since the app starts its server from such a login shell, `ssh-session` saves the environment `docker exec` gives it, which is the container's, and `/etc/profile.d/t3-server-ssh-env.sh` restores it in that session's login shell. The server then sees what the container's own processes see: the tools features put on `PATH`, and variables such as `CLAUDE_CONFIG_DIR`. Only sessions of this entry point are affected.
- **Data:** a named volume per dev container, mounted at `/var/lib/t3-server` with mode `0700`, with the remote user's `~/.t3` linked to it. It holds the server the app downloaded, threads, history, settings and pairing state, so they survive rebuilds.
- **Name:** T3 Code would show the container ID as the environment's name. The feature writes `t3-<folder>` instead, as `PRETTY_HOSTNAME` in `/etc/machine-info`, which T3 Code prefers. The folder is the one mounted at `/workspaces/<folder>`, lowercased, with every character outside `a-z`, `0-9` and `-` replaced by `-`. `t3-dev` names the SSH host from the folder in the same way, so the name you pick when adding the environment is the name it then shows. An existing `/etc/machine-info` that the feature did not write is left alone.
- **Tools the app's installer uses:** `curl` or `wget`, `tar`, `gzip`, `sha256sum`, CA certificates and `libatomic` are installed when missing.

The server runs while the container runs, also after the app disconnects. After the container restarts, it starts again when the app next connects; until then nothing runs, scheduled tasks included.

It does not install or sign in to providers, or persist provider logins.

### Coming from 0.x (`:0`)

Up to 0.3 the feature installed a pinned T3 Code version into the image and started it with the container. That tied every project to one version: an updated desktop app refused the older server until the feature was updated and every container rebuilt. 1.0.0 leaves the server to the app.

The `:0` tag stays on 0.3 and keeps working as before, for as long as the desktop app is 0.0.45. To move, change the reference to `t3-server:1` (in `devcontainer.json` or in `dev.containers.defaultFeatures`) and rebuild. Before you do, check what changes:

- **Use desktop app 0.1.0 or later.** An older app also connects and installs its own server, but that server only shows diffs for directories under the home directory, so the Diff panel stays empty for a project under `/workspaces`. 0.3 avoided that by starting the server from `/`.
- **A non-root `remoteUser` is required.** Root-only images that used `"ssh": false` fail the build, or are skipped with `"strict": false`.
- **Publishing a port is gone**, with `t3-pair` and the `ssh: false` setup. Use the SSH entry point.
- The `version`, `autostart`, `ssh` and `host` options are gone; a build that still sets them prints a note and goes on.
- `t3-server start` and `restart` no longer start anything, but still succeed, so a `postStartCommand` that calls them does no harm. You can remove it.
- Nothing runs in the container until the app connects, scheduled tasks included.
- The first start after the rebuild removes 0.3's server log, which held a pairing token, and its runtime link. Threads and settings in the data volume stay. The first connection then downloads the app's server version, and T3 Code 0.1 copies the earlier threads into its new database on its first start.

## Compatibility

### Images

| Requirement  | Detail |
| ------------ | ------ |
| C library    | glibc. Alpine and other musl images are rejected at build time, because T3 Code publishes no musl build. |
| Architecture | x64 and arm64, the two Linux builds T3 Code publishes. |
| User         | A non-root `remoteUser`. |
| Packages     | `curl` or `wget`, `tar`, `gzip`, `sha256sum`, `bash`, CA certificates, `libatomic`, `runuser` or `setpriv`, an OpenSSH server and `passwd`. |

Missing packages are installed automatically on apt-based images (Debian, Ubuntu) and dnf-based images (Fedora, RHEL family). On anything else the build stops and lists what to add to the base image. Slim images work.

The **Test** workflow in this repository builds a container with the feature and runs the test suite on x64 and arm64 runners, for the images in its matrix and the variants in `test/t3-server/scenarios.json`. One scenario installs and starts a real T3 Code server over the SSH entry point the way the app does. Those are the setups known to work; check the latest run before relying on one that is not among them.

The remote user's UID may differ from the one in the image: dev container tools change it to match the host user. The data volume's owner is repaired at container start when the entrypoint runs as root, or through password-less `sudo` otherwise, and again whenever an SSH session starts.

### Dev container tools

The feature's `entrypoint` names the environment and repairs the volume at container start; the Dev Containers specification leaves running it to each tool, and VS Code does. Where a tool does not, the SSH entry point does the same work when the app connects.

### T3 Code versions

The server always comes from the app itself, so the app and the server are always the same version, and a T3 Code update needs no change here.

Use desktop app 0.1.0 or later. Older apps connect too, but their server shows diffs only for directories under the one it was started in, the home directory, so the Diff panel stays empty for a project under `/workspaces`. 0.1.0 also shows diffs for every project registered with the server.

## Providers

T3 Code drives provider CLIs that must be in the container. For Claude Code, the official feature works:

```jsonc
"features": {
  "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": {}
}
```

Sign in inside the container as usual. Whether that login survives a rebuild depends on the project's own mounts; this feature does not touch provider credentials. Anything a CLI needs from the container's environment reaches the server (see [What the feature does](#what-the-feature-does)); values set only through VS Code's `remoteEnv` do not, because they exist only in VS Code's own processes.

## For every dev container

VS Code can add a feature to every dev container you open, without touching any project. In your user settings:

```jsonc
"dev.containers.defaultFeatures": {
  "ghcr.io/laijunbin/devcontainer-t3code/t3-server:1": { "strict": false }
}
```

Keep `"strict": false` here. Applied to every container, the feature will meet images it cannot support: Alpine, a root-only image, one without a package manager. With `strict` off it prints why and installs nothing, and the container builds as it would have without it.

Things to know:

- This is a VS Code setting. The `devcontainer` CLI and other tools ignore it.
- The provider CLI is still the project's or your own business; add its feature to the same setting if you want it everywhere.
- If a project keeps a `devcontainer-lock.json`, VS Code may record your default features in it. Check before committing that file.
- A container picks the feature up the next time it is rebuilt.

## Connecting without the helper

Anything that can run `docker exec` on the Docker host can carry the connection. An SSH client configuration needs one entry per container:

```
Host t3-myproject
    User vscode
    ProxyCommand docker exec -i -u root <container> /usr/local/share/t3-server/ssh-session
    PubkeyAuthentication no
```

`User` is the dev container's remote user. On Windows with Docker in WSL, prefix the command with `wsl.exe -d <distro> --`. `t3-dev` writes exactly these entries and resolves the container by its workspace folder, so they survive rebuilds.

## Troubleshooting

| Symptom | Cause and fix |
| ------- | ------------- |
| Build fails with `does not use glibc` | The base image is musl-based. Use a glibc image. |
| Build fails with `needs a non-root remoteUser` | Set `remoteUser` in `devcontainer.json`. |
| Build fails with `~/.t3 already exists` | Something else provides `~/.t3` (a mount, or files in the image). Remove it; the feature links that path to its own volume. |
| The first connection takes long | The app is downloading the server (about 90 MB) into the container. It happens once per app version per container. |
| `t3-server status`: not running | The app has not connected since the container started. Connect to the environment in T3 Code. |
| `t3-server`: `is not writable` | The data volume belongs to another UID and could not be repaired, which needs root or password-less `sudo`. Run `docker exec -u root <container> t3-server prepare`. |
| `t3-dev sync` lists nothing | The container is not running, was built without the feature, or the feature skipped itself (`"strict": false`; the build log says why). |
| SSH: `no running dev container for ...` | The container stopped. Start it; no re-sync is needed. |
| SSH: host key changed | The data volume was recreated. Run `t3-dev sync`, which forgets the old key. |
| The provider shows as not installed | Its CLI was not in the container when the server started. Run `t3-server stop`, then reconnect in T3 Code. |
| The environment is named after the container ID | The project is not mounted at `/workspaces/<folder>` (usual for Docker Compose), so the feature cannot tell its folder's name. `t3-dev sync` names it. Without `t3-dev`, or if the image has its own `/etc/machine-info`, set `T3_SERVER_LABEL` in `containerEnv` and rebuild. If the server was already running, run `t3-server stop` and reconnect; then remove the environment in T3 Code and add it again. |
| `T3_SERVER_LABEL` was changed but T3 Code shows the old name | T3 Code keeps the name it got when the environment was added. Remove the environment under **Settings → Connections** and add the same host again; threads live in the container's data volume and stay. |
| Adding an environment replaces another one, or fails with `[ssh_http:401]` | The SSH host now leads to a different container than when T3 Code first connected to it, and the app is still holding the old connection. Quit T3 Code completely and start it again, check hosts and folders with `t3-dev list`, then add the environment. |

## Security notes

- **Where the server comes from.** The app downloads the server from T3 Code's GitHub release and checks it against the `SHA256SUMS` file of the same release. That catches a damaged download, not a release that was replaced as a whole; the desktop app itself comes from the same releases. Up to 0.3 (`:0`) this feature pinned hashes in this repository instead, at the cost of tying every project to one version.
- **No listening surface.** The server listens on loopback inside the container and nothing is published. Other containers and the host cannot connect to it; the only way in is `docker exec`.
- **Password-less SSH, and why.** The SSH entry point accepts the remote user without a key or password. It is reachable only through `docker exec`, which already grants full access to the container, so a key would not keep anyone out. To make this work the feature empties the remote user's password. The image's system SSH configuration keeps `PermitEmptyPasswords` at its default of `no`, so an SSH daemon you run yourself still refuses that login. Do not point another SSH daemon at `/usr/local/share/t3-server/sshd_config`, and do not publish a port to it.
- **The saved environment.** The container's environment, which can include credentials set through `containerEnv`, is saved for SSH sessions in `/run/t3-server/session-env`, readable by the remote user only. Processes of that user can read it, as they can read their own environment.
- **The raw server log can contain an administrative pairing token.** `t3-server logs` filters it out. Do not share the raw files under `~/.t3/ssh-launch/`.
- **Default permission mode.** T3 Code starts new threads in Full access. Every environment has its own settings, so change the default in each new one.
- **What the container boundary gives you.** Agents can read everything in the container, including provider logins mounted into it. They cannot reach the host's files or Docker unless the project mounts them.
